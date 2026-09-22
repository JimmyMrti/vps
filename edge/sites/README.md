# Sites du frontal

> **Avertissement — la machine a divergé de sa procédure.**
> Le frontal réellement en service charge ses fichiers de site depuis
> `/srv/proxy/sites/`, un chemin qui n'existe nulle part dans ce dépôt. Le
> contenu de son `preventioncambriolage.caddy` a été relevé le 22 septembre
> 2026 et se réduit à ceci :
>
> ```caddy
> preventioncambriolage.fr {
>         import commun
>         reverse_proxy site-web:8080
> }
>
> www.preventioncambriolage.fr {
>     redir https://preventioncambriolage.fr{uri} permanent
> }
> ```
>
> Ce qu'il en reste à traiter tient en trois points.
>
> **L'emplacement.** Ces fichiers sont du contenu, pas un chemin — c'est le
> rôle `proxy` du socle qui décide où ils atterrissent. Il faudra l'aligner sur
> `/srv/proxy/sites/` ou aligner la machine sur `/etc/caddy/sites/` ; le
> principe est le même des deux côtés, un fichier par domaine importé par le
> Caddyfile global, seul le chemin diffère. L'arbitrage revient au socle.
>
> **L'extrait `commun`, seule inconnue qui reste.** Chaque bloc en service
> l'importe en première ligne, et le Caddyfile du socle ne le définit pas. Un
> fichier récupéré tel quel fera donc échouer `caddy validate`, ce qui est la
> bonne nouvelle — l'erreur arrive au déploiement, pas devant les visiteurs. La
> mauvaise est l'inverse : **un réglage présent dans `commun` et non repris ici
> disparaîtrait sans bruit.** Il porte vraisemblablement le HSTS, la
> compression et la journalisation, que ce dépôt répartit entre `tls_anssi`
> (socle), `entetes_securite` et `journal_acces`. La correspondance se fait
> ligne à ligne vers ces extraits, jamais en supprimant l'`import` pour faire
> passer la validation.
>
> **Deux écarts volontaires avec l'original**, pour que la comparaison ne les
> prenne pas pour des oublis : le domaine passe ici par `{$SITE_DOMAIN}`, dont
> le défaut est ce même domaine ; et le bloc `www` de l'original n'importe rien
> du tout, donc il ne sert ni HSTS ni en-tête de sécurité, là où celui de ce
> dépôt importe les mêmes extraits que le domaine nu.
>
> Les fichiers `n8n.caddy` et `annuaire.caddy` ne sont pas concernés : ils
> décrivent des services qui n'existent pas encore sur la machine.

Un fichier par domaine, importés par le Caddyfile du socle :

```
import /etc/caddy/sites/*.caddy
```

L'ordre est alphabétique, d'où le préfixe numérique sur les fichiers qui
définissent des extraits réutilisables : ils doivent être lus **avant** les
fichiers qui les importent.

Le dossier est monté en lecture seule dans le conteneur Caddy :

```yaml
volumes:
  - ./edge/sites:/etc/caddy/sites:ro
```

## Ce que le Caddyfile du socle doit fournir

Ces fichiers en dépendent, et ne s'utilisent donc jamais seuls :

| Élément | Rôle |
|---|---|
| `import /etc/caddy/sites/*.caddy` | ce qui les charge |
| l'extrait `(tls_anssi)` | le profil TLS, importé par chaque bloc de site |
| le dossier `/var/log/caddy` monté depuis l'hôte | l'extrait `journal_acces` y écrit, et fail2ban le lit |
| les variables ci-dessous, dans l'environnement du conteneur | les domaines et les listes d'adresses |

Les extraits `(entetes_securite)` et `(journal_acces)`, eux, sont définis ici
même, dans `00-extraits.caddy`.

## Variables attendues dans l'environnement de Caddy

Ces fichiers lisent leur configuration dans l'environnement du conteneur
Caddy — c'est la pile du frontal, côté socle, qui doit les fournir.

| Variable | Rôle | Si vide |
|---|---|---|
| `SITE_DOMAIN` | preventioncambriolage.fr | `preventioncambriolage.fr` |
| `SITE_AMONT` | le conteneur qui sert le site, pour une bascule en deux temps | `web:8080`, le nom de la pile cible |
| `N8N_DOMAIN` | domaine de n8n, étiquette aléatoire sous le domaine d'infrastructure | `n8n.localhost`, donc inactif publiquement |
| `N8N_IP_ADMIN` | adresses autorisées sur l'interface n8n | `192.0.2.1`, adresse de documentation : personne n'entre |
| `ANNUAIRE_DOMAIN` | domaine de l'annuaire | `annuaire.localhost`, donc inactif |
| `ANNUAIRE_IP_PRIVE` | adresses autorisées avant l'ouverture publique, si le bloc dédié est décommenté | `192.0.2.1` |

Les filtres d'adresses utilisent le matcher `client_ip` et non `remote_ip` :
le premier tient compte des mandataires déclarés de confiance dans le
Caddyfile du socle, le second regarde seulement le pair direct. Aujourd'hui les
deux donnent le même résultat, le frontal étant en bout de chaîne ; le jour où
quelque chose se place devant, seul `client_ip` reste juste.

Les valeurs par défaut sont choisies pour **échouer du bon côté** : un domaine
non renseigné donne un nom en `.localhost`, pour lequel Caddy fabrique un
certificat interne sans rien demander à Let's Encrypt, et une liste d'adresses
vide n'ouvre rien à personne.

## Essais de certificat

Pour un nouveau sous-domaine, passer d'abord par le serveur de test de Let's
Encrypt (`acme_ca` en mode staging dans le Caddyfile du socle) : le quota est
de **5 certificats identiques par semaine**, et on l'atteint vite en tâtonnant.
