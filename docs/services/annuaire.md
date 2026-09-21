# Annuaire artisans enrichi

Le site n'existe pas encore. Ce document ne décide donc pas de son code : il
décide **de quoi il aura besoin pour tourner ici**, et quelles contraintes il
devra respecter pour être hébergeable sans rouvrir le sujet de la sécurité.

---

## Contrat d'exécution

L'application est livrée comme **une image Docker construite en intégration
continue**, jamais compilée sur le VPS. C'est le modèle déjà en place pour
preventioncambriolage : le serveur n'héberge ni sources, ni Node, ni chaîne de
compilation, et une mise à jour se résume à tirer une image.

Ce que l'image doit respecter :

| Exigence | Raison |
|---|---|
| écoute en **HTTP simple sur 8080** | la terminaison TLS est au frontal, l'application n'a pas à connaître de certificat |
| **ne tourne pas en root** (`USER` non privilégié dans le Dockerfile) | une évasion de conteneur part alors d'un compte sans droits |
| **aucun état sur le disque local** hors volumes déclarés | un conteneur doit pouvoir être détruit et recréé sans perte |
| configuration **par variables d'environnement** uniquement | rien à modifier dans l'image entre préproduction et production |
| point de santé sur `/healthz` répondant 200 | sans quoi le frontal envoie du trafic à un conteneur qui démarre encore |
| **migrations de schéma dans une commande séparée** | elles s'exécutent avant le démarrage, pas au démarrage : deux conteneurs qui migrent en même temps corrompent la base |
| lit `X-Forwarded-For` et `X-Forwarded-Proto` | sinon toutes les visites semblent venir de Caddy, et les URL générées sont en `http://` |

La migration s'exécute par un profil dédié :

```bash
docker compose --profile migration run --rm migration
docker compose up -d
```

C'est volontairement en deux temps. Une migration lancée automatiquement au
démarrage du conteneur applicatif rend impossible un déploiement qu'on veut
annuler.

---

## Base de données

**PostgreSQL 16, instance dédiée, avec PostGIS.**

Trois questions ont été tranchées :

**Une instance ou une base dans l'instance de n8n ?** Instance dédiée. Deux
bases dans un même PostgreSQL partagent le même processus et le même rôle
superutilisateur : une injection SQL exploitée d'un côté finit par lire l'autre.
Le surcoût est d'environ 150 Mo de mémoire, ce qui est peu cher payé quand un
côté détient des identifiants d'API et l'autre des données de personnes.

**PostGIS ou pas ?** Oui. Un annuaire d'artisans se consulte « autour de chez
moi » : la recherche par distance est la fonction centrale, pas un
enrichissement. La faire à la main avec des calculs de latitude et longitude
donne des résultats faux dès qu'on approche des bords, et empêche d'indexer.
`ST_DWithin` sur un index GiST règle le sujet une fois pour toutes.

**Un moteur de recherche séparé (Elasticsearch, Meilisearch) ?** Non, pas au
début. PostgreSQL sait faire de la recherche plein texte en français avec
`unaccent` et `pg_trgm`, ce qui couvre « plombier chauffagiste » saisi sans
accents et avec une faute. Un moteur dédié, c'est 500 Mo à 1 Go de mémoire en
plus et un second entrepôt à synchroniser et à sauvegarder. On l'ajoutera si la
recherche devient le point faible mesuré, pas par anticipation.

Extensions activées au premier démarrage
([`services/annuaire/initdb/`](../../services/annuaire/initdb/)) : `postgis`,
`pg_trgm`, `unaccent`.

---

## Sources de données et statut de diffusion

Un annuaire d'artisans se construit à partir de bases publiques — répertoire
Sirene de l'INSEE, qualifications RGE, annuaire des entreprises. **Ces données
sont publiques mais pas librement rediffusables en bloc.**

Le point dur, concret et vérifiable : le répertoire Sirene porte un indicateur
`statutDiffusionUniteLegale`. Une unité légale marquée `P` est **partiellement
diffusible** — typiquement un entrepreneur individuel qui s'est opposé à la
diffusion. Pour celles-ci, **le nom, le prénom et l'adresse ne doivent pas être
publiés**. Rediffuser une base Sirene sans filtrer ce champ, c'est publier les
coordonnées personnelles de gens qui ont explicitement demandé le contraire.

La règle tenue ici : **le filtre s'applique à l'import, pas à l'affichage.** Une
donnée non diffusible n'entre pas dans la base publique du site. Un filtre au
moment de l'affichage finit toujours par être contourné par une API, un export
ou un flux oublié.

Le détail des obligations est dans
[`donnees-personnelles.md`](donnees-personnelles.md).

---

## Domaine

**Recommandation : un domaine propre, pas un sous-domaine de
`preventioncambriolage.fr`.**

Contrairement à n8n, l'annuaire est un site public destiné à être indexé, et
c'est ce qui change la réponse. Un sous-domaine lie les deux réputations : une
sanction de référencement sur l'un rejaillit sur l'autre, et l'annuaire ne peut
plus être cédé ni hébergé ailleurs sans changer d'adresse — donc sans repartir
de zéro côté référencement. Une dizaine d'euros par an évite les deux, et le
DNS est déjà géré chez OVH.

Le nom n'est pas un détail technique : c'est le premier actif du site. Trois
directions, par ordre de préférence, à vérifier disponibles chez OVH :

| Direction | Exemple | Ce que ça donne |
|---|---|---|
| le service rendu | `trouver-un-artisan.fr` | compréhensible sans explication, bon pour les liens entrants |
| la promesse | `artisans-verifies.fr` | engage sur la vérification, donc oblige à la tenir |
| une marque courte | un mot inventé de 6 à 9 lettres | mémorisable, mais tout est à construire |

La première direction est la plus sûre quand le site part de zéro : le nom fait
la moitié du travail d'explication.

Tant que le domaine n'est pas choisi, rien ne bloque : `edge/sites/annuaire.caddy`
sert un nom en `.localhost`, pour lequel Caddy fabrique un certificat interne
sans rien demander à Let's Encrypt. Le site est donc développable et
déployable, simplement pas public.

**Pas de préproduction sur ce VPS.** Elle vivrait à côté des données réelles,
et une application de préproduction qui a le droit d'écrire dans la base de
production est un accident qui attend son heure. Elle doublerait de surcroît la
consommation mémoire — voir [`dimensionnement.md`](dimensionnement.md). La mise
au point se fait sur une pile locale, comme le site statique le fait déjà avec
`make dev`.

Le garde-fou de lancement est le même que celui du site statique :
`ANNUAIRE_INDEXABLE=0` interdit tout dans `robots.txt` et pose un `noindex` sur
chaque page, jusqu'au jour de l'ouverture. Le bloc de restriction par adresse
IP prévu dans `edge/sites/annuaire.caddy` complète ce garde-fou pendant la mise
au point.

**Pour les essais de certificat sur un nouveau sous-domaine, passer par le
serveur de test de Let's Encrypt** (`acme_ca` en mode staging dans le Caddyfile
du socle) : le quota est de 5 certificats identiques par semaine, et on
l'atteint vite en tâtonnant.
