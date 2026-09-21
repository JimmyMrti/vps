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

Le socle infra as code et l'ajout des deux nouveaux services suivent.
