# État réel du VPS

Ce document décrit la machine telle qu'elle tourne, d'après le relevé
`scripts/releve-vps.sh` du **24 septembre 2026 à 20 h 49 UTC**
(`vps-54392dab.vps.ovh.net`). Il fait foi sur tout autre document du projet
qui décrit le serveur, `docs/vps.md` du dépôt du site en tête : ce dernier
parle de `/opt/`, qui ne contient rien de l'application.

Pour le mettre à jour, relancer le relevé (voir `docs/releve-vps.md`) et
reporter les écarts ici.

Ce document décrit l'architecture. L'évaluation de sécurité (comptes,
configuration SSH, écarts aux recommandations de l'ANSSI) et les corrections
qui en découlent sont tenues hors du dépôt, dans les fichiers privés du
projet (`releves/etat-reel-vps-failles.md`) : une liste de failles ouvertes
n'a pas sa place dans un historique git.

## Vue d'ensemble

```
Internet ──► ens3  (IPv4 + IPv6)
               │
               ├─ 22/tcp   sshd (authentification par clé)
               │
               └─ 80/tcp, 443/tcp, 443/udp ─► docker-proxy
                                               │
                     réseau Docker « edge » 172.19.0.0/16 (externe, partagé)
                     ┌─────────────────────────┴──────────────────────────┐
                     │ proxy-caddy-1          caddy:2.8-alpine (v2.8.4)   │
                     │   /srv/proxy           TLS Let's Encrypt, HTTP/3   │
                     │        │ reverse_proxy site-web:8080               │
                     │        ▼                                           │
                     │ preventioncambriolage-web-1   (alias : site-web)   │
                     │   ghcr.io/jimmymrti/preventioncambriolage:latest   │
                     │   nginx, lecture seule, sans capacité, 128 Mo      │
                     └────────────────────────────────────────────────────┘

systemd : maj@preventioncambriolage.timer (toutes les 10 min)
          └─► /usr/local/bin/maj-application preventioncambriolage
                docker compose pull ; up -d si l'image a changé
```

## Machine

| | |
|---|---|
| Système | Ubuntu 26.04 LTS (`resolute`), noyau 7.0.0-31-generic |
| Ressources | 4 vCPU, 7,6 Gio de RAM (730 Mio utilisés), pas de swap |
| Disque | `/dev/sda1` ext4 72 Go, 3,8 Go utilisés (6 %) ; `/boot` 1 Go ; `/boot/efi` 105 Mo |
| Réseau | IPv4 par DHCP ; IPv6 fixe en `/128` dans `/etc/netplan/50-cloud-init.yaml`, `accept-ra: false` ; résolveur DNS d'OVH |
| Horloge | chrony |
| Allumée depuis | 13 jours au moment du relevé |

Paquets ajoutés à l'image OVH : `docker-ce`, `docker-ce-cli`, `containerd.io`,
`docker-buildx-plugin`, `docker-compose-plugin` (dépôt `download.docker.com`,
clé `/etc/apt/keyrings/docker.asc`), `fail2ban`, `ufw`, `unattended-upgrades`.
Docker Engine 29.7.2, Compose v5.5.0.

## Accès

SSH par clé uniquement, un seul compte autorisé, qui administre par `sudo` et
appartient au groupe `docker` (ce qui équivaut à être root). Le durcissement
de sshd est dans `/etc/ssh/sshd_config.d/99-hardening.conf` ; le transfert de
port TCP reste permis, pour le tunnel vers l'éditeur n8n.

## Réseau et pare-feu

UFW actif, politique entrante par défaut « refuser », six règles (IPv4 et
IPv6) : `OpenSSH`, `80/tcp`, `443/tcp`, `443/udp`. Aucune autre écoute
publique que sshd et `docker-proxy` sur 80 et 443. Les journaux système ne
montrent que des balayages de ports bloqués par UFW.

Les ports de Caddy sont publiés sans préfixe d'adresse, donc ouverts par
Docker directement dans iptables, en amont d'UFW. C'est voulu pour 80 et 443,
mais toute publication future sans `127.0.0.1:` serait ouverte au monde quoi
qu'en dise UFW.

## Services de sécurité

UFW, fail2ban (prison `sshd` sur le journal systemd, action nftables),
mises à jour automatiques quotidiennes avec redémarrage à 04 h 30 si un
correctif l'exige (`/etc/apt/apt.conf.d/51redemarrage`), AppArmor avec le
profil `docker-default` sur les conteneurs. Aucun réglage sysctl propre à la
machine.

## Docker

| Objet | Détail |
|---|---|
| Réseaux | `edge` (bridge, externe, 172.19.0.0/16) partagé par les deux projets ; `bridge` par défaut inutilisé |
| Volumes | `proxy_caddy_data` (certificats, 12 ko) et `proxy_caddy_config` |
| Images | le site (`latest`, 88 Mo), Caddy, plus **14 anciennes images du site sans étiquette**, `alpine` et `hello-world` inutilisés |
| Journaux des conteneurs | `json-file`, 3 × 10 Mo par conteneur |

### Projet `proxy` — `/srv/proxy/`

```
/srv/proxy/
├── .env                  ACME_EMAIL (0600)
├── Caddyfile             options globales + extrait « commun » + import sites/*.caddy
├── docker-compose.yml
└── sites/
    └── preventioncambriolage.caddy
```

Conteneur `proxy-caddy-1`, image `caddy:2.8-alpine` (Caddy v2.8.4).
L'étiquette est épinglée et se change à la main : le frontal n'a pas de
mise à jour automatique. Redémarrage `unless-stopped`, `no-new-privileges`.

L'extrait `commun` ajoute la compression zstd/gzip, l'en-tête
`Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"`,
retire l'en-tête `Server` et journalise les accès sur la sortie standard.
Aucun profil TLS n'est déclaré : Caddy applique ses réglages par défaut
(TLS 1.2 et 1.3).

`sites/preventioncambriolage.caddy` :

```caddy
preventioncambriolage.fr {
	import commun
	reverse_proxy site-web:8080
}
www.preventioncambriolage.fr {
    redir https://preventioncambriolage.fr{uri} permanent
}
```

Certificats détenus : `preventioncambriolage.fr` (obtenu le 22 août 2026) et
`www.preventioncambriolage.fr` (obtenu le 22 septembre 2026).

### Projet `preventioncambriolage` — `/srv/preventioncambriolage/`

```
/srv/preventioncambriolage/
├── .docker/config.json   identifiants ghcr.io (root, 0600)
├── .env                  IMAGE (0600)
└── docker-compose.yml
```

Conteneur `preventioncambriolage-web-1` (projet `preventioncambriolage`,
service `web`), joignable sous l'alias **`site-web`** sur le réseau `edge`.
C'est l'alias que vise Caddy, pas le nom du conteneur. Réglages :
utilisateur `nginx`, racine en lecture seule, `tmpfs` sur `/tmp` et
`/var/cache/nginx`, `cap_drop: ALL`, `no-new-privileges`, 128 Mo de mémoire,
128 processus, aucun port publié, `pull_policy: always`, sonde de santé au
vert. Image du 24 septembre 2026, révision `234c618` du dépôt du site.

### Mise à jour automatique

Mécanisme générique, prêt à servir pour d'autres applications :

- `/etc/systemd/system/maj@.timer` : 3 min après le démarrage puis toutes les
  10 min, décalage aléatoire d'une minute ;
- `/etc/systemd/system/maj@.service` : lance
  `/usr/local/bin/maj-application %i` en root, avec
  `DOCKER_CONFIG=/srv/%i/.docker`, `ProtectSystem=strict` et écriture limitée
  à `/srv/%i` ;
- `maj-application <nom>` lit `IMAGE` dans `/srv/<nom>/.env`, fait un
  `docker compose pull`, et relance avec `up -d --remove-orphans` seulement si
  l'empreinte de l'image a changé, puis supprime les images de plus de 7 jours.

Seule l'instance `maj@preventioncambriolage` existe. Le frontal n'a pas
d'instance : sa configuration et son image se changent à la main.

## Ce qui n'existe pas sur la machine

- Rien sous `/opt/` hormis `containerd`.
- Aucun dépôt git : tous les fichiers de `/srv/` ont été déposés à la main
  (22 et 23 août 2026, fichier de site modifié le 22 septembre).
- Aucune tâche cron propre, aucune sauvegarde planifiée.
- Ni n8n, ni annuaire, ni base de données.

## Écarts avec ce que le projet croyait

| Croyance | Réalité |
|---|---|
| `docs/vps.md` : déploiement dans `/opt/preventioncambriolage/docker/` | tout est sous `/srv/` |
| Le conteneur du site s'appelle `site-web` (projet `site`) | il s'appelle `preventioncambriolage-web-1` (projet `preventioncambriolage`) ; `site-web` est un alias réseau |
