# VPS OVH — infrastructure as code

Description, en code, du VPS OVH qui héberge :

- **preventioncambriolage.fr**, site statique déjà en production ;
- **n8n**, serveur d'automatisation ;
- un **annuaire artisans enrichi**, site applicatif.

La cible est un serveur dont l'état se décrit et se rejoue depuis ce dépôt,
durci d'après les recommandations de l'ANSSI.

---

## La machine

VPS 2 chez OVH : 4 vCores, 8 Go de mémoire, 75 Go de disque, Ubuntu 26.04.
Le DNS des domaines est chez OVH également.

## Les trois règles qui tiennent l'ensemble

**Un seul conteneur publie des ports** — le frontal Caddy, et lui seul. Tant
que c'est vrai, la surface exposée se résume à 80, 443 et SSH, quel que soit
le nombre de services.

**Une base de données ne voit jamais l'extérieur** — chaque pile a son réseau
interne, où le frontal n'entre pas et d'où l'on ne sort pas.

**Rien ne se construit sur la machine** — les images sont fabriquées par
GitHub Actions, le serveur va les chercher. GitHub n'a donc aucun accès au
serveur.

---

## Démarrer

```bash
# Ce que ferait le playbook, sans rien changer
cd ansible && ansible-playbook site.yml --check --diff

# Le socle seul, sans toucher aux services
ansible-playbook durcissement.yml

# Constater l'état de la machine
ansible-playbook verification.yml
```

L'installation complète, pas à pas, est dans
[`docs/exploitation.md`](docs/exploitation.md).

> **Le site tourne déjà.** Avant de jouer quoi que ce soit sur la machine de
> production, lisez
> [`docs/migration-site-existant.md`](docs/migration-site-existant.md) : la
> bascule vers le frontal mutualisé est le seul moment réellement risqué de ce
> chantier, et elle se prépare.

---

## Organisation

| Dossier | Contenu |
|---|---|
| `terraform/` | ce qui vit chez OVH : DNS, reverse DNS, politique de courrier, CAA |
| `ansible/` | ce qui vit sur la machine : système, durcissement, Docker, frontal |
| `edge/sites/` | un fichier Caddy par domaine servi |
| `services/` | les piles applicatives et leur exploitation |
| `docs/` | architecture, conformité, exploitation, décisions |
| `docs/adr/` | les décisions et leurs raisons |

### Les rôles Ansible

| Rôle | Ce qu'il fait |
|---|---|
| `socle` | paquets, modules noyau, sysctl, montages, AppArmor |
| `comptes` | compte d'administration, sudo journalisé, comptes de service |
| `ssh` | authentification par clé, algorithmes, `moduli` |
| `pare_feu` | nftables **et** la chaîne `DOCKER-USER` |
| `fail2ban` | jail `sshd` |
| `mises_a_jour` | correctifs de sécurité automatiques |
| `journalisation` | journaux persistants, `auditd` |
| `docker` | moteur, durcissement du démon, réseau `edge`, ménage des images |
| `proxy` | le frontal Caddy, qui importe `edge/sites/*.caddy` |
| `site_statique` | le site en production |
| `maj_service` | mise à jour en mode « pull », générique |
| `supervision` | contrôles locaux périodiques |

---

## Documents

| Document | Contenu |
|---|---|
| [`docs/architecture.md`](docs/architecture.md) | ce que contient la machine et pourquoi c'est disposé ainsi |
| [`docs/conformite-anssi.md`](docs/conformite-anssi.md) | ce qui est appliqué, guide par guide, **et les écarts assumés** |
| [`docs/exploitation.md`](docs/exploitation.md) | installer, exploiter, dépanner |
| [`docs/migration-site-existant.md`](docs/migration-site-existant.md) | reprendre le site sans le couper |
| [`docs/secrets.md`](docs/secrets.md) | où vivent les secrets, comment les changer |
| [`docs/inventaire-existant.md`](docs/inventaire-existant.md) | ce qui tourne aujourd'hui pour preventioncambriolage.fr |

### Décisions

| Décision | Sujet |
|---|---|
| [`0001`](docs/adr/0001-terraform-et-ansible.md) | Terraform autour, Ansible dedans, et pourquoi le VPS n'est pas décrit |
| [`0002`](docs/adr/0002-nftables-et-le-contournement-docker.md) | nftables, et le filet qui rattrape le contournement par Docker |
| [`0003`](docs/adr/0003-acme-http-01.md) | validation ACME par HTTP-01, pas par DNS-01 |
| [`0004`](docs/adr/0004-le-serveur-va-chercher-ses-mises-a-jour.md) | le serveur va chercher ses mises à jour |
| [`0005`](docs/adr/0005-un-domaine-par-service.md) | un domaine par service, aucun sous-domaine partagé |

---

## Deux principes à ne pas défaire

**Aucune application ne publie de port.** Le frontal est le seul point
d'entrée. La chaîne `DOCKER-USER` rattrape l'oubli, mais elle est un filet,
pas une autorisation.

**Le port 80 ne se ferme jamais.** Il porte le challenge ACME à chaque
renouvellement. Le fermer produit une panne à retardement : tout fonctionne
pendant deux mois, puis les certificats expirent.
