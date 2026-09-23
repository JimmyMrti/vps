# Dimensionnement

## La machine

> **OVH VPS 2 — 4 vCores, 8 Go de mémoire, 75 Go de disque, Ubuntu 26.04.**

C'est confortable pour les trois services, à condition de poser des limites :
la mémoire est la ressource contrainte, pas le processeur. Quatre cœurs
absorbent sans difficulté un site statique, un annuaire et des workflows qui
s'exécutent par à-coups ; 8 Go se remplissent, eux, beaucoup plus vite qu'on
ne l'imagine dès qu'une base de données et un runtime Node coexistent.

---

## Ce que chaque service consomme

Mesures d'ordre de grandeur, au repos puis en charge normale :

| Service | Mémoire au repos | Pic courant | CPU | Disque |
|---|---|---|---|---|
| Caddy | 30 Mo | 80 Mo | négligeable | 50 Mo (certificats) |
| site statique (nginx) | 15 Mo | 40 Mo | négligeable | inclus dans l'image |
| n8n | 400 Mo | 900 Mo | par à-coups | 500 Mo (binaires, cache) |
| PostgreSQL n8n | 120 Mo | 300 Mo | faible | 1 à 5 Go selon l'historique |
| annuaire (application) | 250 Mo | 700 Mo | soutenu en pointe | inclus dans l'image |
| PostgreSQL + PostGIS annuaire | 200 Mo | 600 Mo | selon les requêtes | 5 à 20 Go |
| **Total** | **~1,0 Go** | **~2,6 Go** | | **~30 Go avec les images et sauvegardes locales** |

n8n est l'ogre de la liste, et de façon irrégulière : un workflow qui manipule
un gros fichier charge tout en mémoire. C'est précisément pour cela qu'il a une
limite.

---

## Limites par conteneur

Chaque service porte une limite mémoire dans son `docker-compose.yml`. Sans
elles, le premier workflow n8n gourmand fait intervenir le tueur de processus
du noyau, qui choisit sa victime **sur des critères qui n'ont rien à voir avec
l'importance du service** — en pratique, souvent PostgreSQL.

| Conteneur | Limite mémoire | Réservation |
|---|---|---|
| `n8n` | 1,5 Go | 512 Mo |
| `n8n-db` | 512 Mo | 256 Mo |
| `annuaire` | 1 Go | 256 Mo |
| `annuaire-db` | 1,5 Go | 512 Mo |
| `site` | 128 Mo | — |
| `caddy` | 256 Mo | — |

Total des limites : 4,9 Go sur 8 Go. La marge n'est pas du gaspillage : elle
absorbe le cache disque du noyau, sans lequel PostgreSQL rame, et les pics de
déploiement où deux versions d'un conteneur coexistent.

Une limite atteinte tue le conteneur, qui redémarre — c'est visible et
diagnostiquable (`docker events`, code de sortie 137). Un serveur qui part en
mémoire virtuelle, non.

---

## Échange (swap) et paramètres noyau

Un VPS sans échange se fige brutalement au lieu de ralentir. Un VPS qui en
abuse devient inutilisable sans qu'on comprenne pourquoi.

```ini
# 2 Go d'échange, utilisé seulement en dernier recours
vm.swappiness = 10
vm.overcommit_memory = 2
vm.overcommit_ratio = 80
```

`overcommit_memory=2` est le réglage que PostgreSQL recommande : il fait échouer
une allocation impossible au moment où elle est demandée, plutôt que de
promettre de la mémoire qui n'existe pas et de laisser le tueur de processus
trancher plus tard.

**Ces réglages relèvent du socle**, ils sont notés ici parce que le
dimensionnement n'a pas de sens sans eux.

---

## Disque

| Poste | Taille |
|---|---|
| système et Docker | 10 Go |
| images (3 services, 2 versions conservées) | 6 Go |
| base n8n avec 7 jours d'historique | 2 Go |
| base annuaire | 5 à 20 Go |
| sauvegardes locales (3 jours) | 5 Go |
| **Total** | **30 à 45 Go** |

Les 75 Go suffisent, à deux conditions :

- **purger les images remplacées** — c'est déjà ce que fait `maj.sh` avec
  `docker image prune --filter until=168h` ;
- **limiter les journaux**, déjà en place avec `max-size: 10m` et
  `max-file: 3` par conteneur. Six conteneurs, c'est 180 Mo plafonnés au lieu
  d'une croissance sans fin.

Une alerte à 80 % d'occupation tourne deux fois par jour
([`surveillance-disque.sh`](../../services/_commun/surveillance-disque.sh)) et
affiche directement les postes les plus lourds, pour que l'alerte soit
exploitable sans se connecter. **Un disque plein sur un VPS qui héberge une
base de données, c'est une corruption possible, pas seulement un service
indisponible** : PostgreSQL ne peut plus écrire ses journaux de transaction et
s'arrête en catastrophe.

Les trois mécanismes qui empêchent d'y arriver sont en place dès l'installation,
et pas ajoutés le jour où le disque est plein :

| Mécanisme | Où |
|---|---|
| purge de l'historique n8n à 7 jours | `EXECUTIONS_DATA_PRUNE` dans `services/n8n/docker-compose.yml` |
| purge des images remplacées à 7 jours | `docker image prune` dans le script de mise à jour |
| rotation des journaux, 10 Mo × 3 par conteneur | `x-journalisation` dans chaque pile |
| purge des vidages locaux à 3 jours | `sauvegarde.sh` |

---

## La marge, et le jour où elle se réduit

Les limites totalisent 4,9 Go sur 8 Go. Si un besoin nouveau vient mordre dans
la marge, voici ce qu'on peut concéder, dans cet ordre :

| Changement | Conséquence |
|---|---|
| `EXECUTIONS_DATA_MAX_AGE=72` (3 jours) | fenêtre de diagnostic réduite, aucune perte fonctionnelle |
| `n8n` limité à 1 Go | les workflows manipulant de gros fichiers échouent |
| `annuaire-db` limité à 1 Go | recherche plus lente, moins de cache |

Ce qui n'est **jamais** une bonne réponse au manque de mémoire : retirer les
limites. Sans elles la machine ne tombe pas moins, elle tombe de façon moins
prévisible — et c'est rarement le conteneur fautif qui est tué.

---

## Montée en charge, le jour venu

Dans l'ordre où cela se pose :

1. **Trafic sur l'annuaire** — le premier levier est le cache au frontal sur
   les pages de liste, pas une machine plus grosse.
2. **Recherche lente** — vérifier les index avant d'ajouter un moteur dédié.
   Une recherche sans index GiST sur un million de lignes est lente sur
   n'importe quelle machine.
3. **n8n saturé** — passer en mode file d'attente (Redis + workers). Cela
   double la mémoire consommée ; c'est le moment de séparer n8n sur sa propre
   machine plutôt que de grossir celle-ci.

Séparer n8n est d'ailleurs aussi le bon geste de sécurité : c'est le service
qui exécute du code arbitraire, et le sortir de la machine qui sert les sites
publics supprime d'un coup toute la question du cloisonnement local.
