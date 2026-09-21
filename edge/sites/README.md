# Sites du frontal

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
