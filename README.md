# VPS OVH — infrastructure as code

Description, en code, du VPS OVH qui héberge :

- **preventioncambriolage.fr**, site statique déjà en production ;
- **n8n**, serveur d'automatisation (à venir) ;
- un **annuaire artisans enrichi**, site applicatif (à venir).

La cible est un serveur dont l'état se décrit et se rejoue depuis ce dépôt,
durci d'après les recommandations de l'ANSSI.

## Où en est le dépôt

| Document | Contenu |
|---|---|
| [`docs/inventaire-existant.md`](docs/inventaire-existant.md) | ce qui tourne aujourd'hui pour preventioncambriolage.fr : stack, build, déploiement, domaine, TLS, secrets, posture de sécurité, contraintes de migration |
| [`docs/services/`](docs/services/) | l'accueil de n8n et de l'annuaire artisans : cloisonnement, bases de données, dimensionnement, exposition, sauvegardes, données personnelles |
| [`services/`](services/) | les piles Docker Compose des services applicatifs, leurs sauvegardes et leurs unités systemd |
| [`edge/sites/`](edge/sites/) | un fichier de configuration Caddy par domaine, importés par le frontal mutualisé |

Le socle infra as code suit.
