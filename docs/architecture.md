# Architecture

Ce que contient la machine, et pourquoi c'est disposé ainsi.

---

## Vue d'ensemble

```
                          Internet
                             │
                    ┌────────┴────────┐
                    │  80 / 443 (tcp) │   les SEULS ports publiés
                    │  443 (udp, h3)  │   par un conteneur
                    └────────┬────────┘
                             │
   ╔═════════════════════════╪═════════════════════════════════════╗
   ║  VPS OVH — nftables (entrée en rejet) + DOCKER-USER           ║
   ║                         │                                     ║
   ║                  ┌──────┴──────┐                              ║
   ║                  │   frontal   │  Caddy : TLS, ACME, HSTS     ║
   ║                  │   (Caddy)   │  importe edge/sites/*.caddy  ║
   ║                  └──────┬──────┘                              ║
   ║                         │  réseau « edge »                    ║
   ║        ┌────────────────┼────────────────┐                    ║
   ║        │                │                │                    ║
   ║   ┌────┴────┐     ┌─────┴─────┐    ┌─────┴──────┐             ║
   ║   │   web   │     │    n8n    │    │  annuaire  │             ║
   ║   │ (nginx) │     │           │    │            │             ║
   ║   └─────────┘     └─────┬─────┘    └─────┬──────┘             ║
   ║    statique             │                │                    ║
   ║    sans état     ┌──────┴──────┐   ┌─────┴──────┐             ║
   ║                  │  PostgreSQL │   │ PostgreSQL │             ║
   ║                  └─────────────┘   └────────────┘             ║
   ║                  réseau interne    réseau interne             ║
   ║                  (sans route vers l'extérieur)                ║
   ╚═══════════════════════════════════════════════════════════════╝
```

## Les trois règles qui tiennent l'ensemble

**1. Un seul conteneur publie des ports.** Le frontal, et lui seul. Tant que
c'est vrai, la surface exposée se résume à 80, 443 et SSH, quel que soit le
nombre de services. Un `ports:` ajouté ailleurs contournerait le pare-feu de
l'hôte : voir [`adr/0002`](adr/0002-nftables-et-le-contournement-docker.md),
et la chaîne `DOCKER-USER` qui sert de filet.

**2. Une base de données ne voit jamais l'extérieur.** Chaque pile a son
réseau interne, déclaré `internal`, où le frontal n'entre pas et d'où l'on ne
sort pas. Une base n'a aucune raison d'être joignable depuis le point d'entrée
HTTP, ni d'appeler l'Internet.

**3. Rien ne se construit sur la machine.** Les images sont fabriquées par
GitHub Actions ; le serveur va les chercher. Ni Node, ni sources, ni chaîne
de compilation. Voir [`adr/0004`](adr/0004-le-serveur-va-chercher-ses-mises-a-jour.md).

---

## Partage du travail entre les fils

Ce dépôt est écrit par plusieurs chantiers en parallèle. La frontière :

| Ce dépôt décrit | Qui le porte |
|---|---|
| Système : paquets, comptes, SSH, pare-feu, journalisation, audit | **socle** (`ansible/roles/`) |
| Moteur Docker, réseau `edge`, identifiants de registre | **socle** |
| Frontal Caddy : conteneur, options globales, TLS, volumes | **socle** |
| Site statique en production, et sa bascule sous le frontal | **socle** |
| Mise à jour en mode « pull », générique | **socle** |
| Un fichier Caddy par domaine (`edge/sites/*.caddy`) | **services** |
| Piles n8n et annuaire (`services/`) | **services** |
| Sauvegardes, restauration d'essai, surveillance du disque | **services** |
| Jails fail2ban visant le frontal | **services** |
| Inventaire de l'existant (`docs/inventaire-existant.md`) | **inventaire** |

Le contrat entre le socle et les services est le dossier `edge/sites/` : le
socle fournit le conteneur Caddy et les variables d'environnement, les
services fournissent un fichier par domaine. Il est décrit dans
`edge/sites/README.md`.

---

## Arborescence sur le serveur

```
/opt/vps/
├── frontal/
│   ├── Caddyfile            options globales + import des sites
│   ├── sites/               un fichier par domaine, déployé depuis le dépôt
│   ├── compose.yml
│   └── .env                 SITE_DOMAIN, N8N_DOMAIN, N8N_IP_ADMIN…
├── site/
│   ├── compose.yml
│   └── maj.sh               mise à jour en pull
└── …                        les piles applicatives, côté services

/etc/docker/identifiants/    jeton ghcr en lecture seule, 0700
/var/log/caddy/              journal d'accès, lu par fail2ban
```

Une seule racine, `/opt/vps`, surveillée d'un bloc par `auditd`.

---

## Pourquoi pas de supervision lourde

Prometheus et Grafana sur cette machine ajouteraient deux services exposés,
deux bases et plusieurs gigaoctets de séries temporelles sur un disque de
75 Go — pour surveiller trois services.

Ce qui est fait à la place : des contrôles locaux toutes les quinze minutes
qui écrivent dans le journal et font apparaître l'unité en échec.

Ce qui reste à faire, et qu'aucun logiciel sur cette machine ne peut faire :
**une sonde externe**. Un serveur en panne ne peut pas signaler sa panne.
Voir [`exploitation.md`](exploitation.md).
