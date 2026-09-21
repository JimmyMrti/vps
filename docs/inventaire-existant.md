# Inventaire de l'existant — preventioncambriolage.fr

Relevé fait le 21 septembre 2026 sur le dépôt `JimmyMrti/preventioncambriolage`,
commit `3b66b28`. Tout ce qui suit est lu dans le dépôt, pas supposé. Les points
non vérifiables depuis cet environnement sont signalés comme tels.

Ce document sert de base aux deux chantiers suivants : le socle infra as code du
VPS, puis l'ajout de n8n et de l'annuaire artisans.

---

## 1. Ce qui tourne aujourd'hui

Un site **statique**, sans base de données, sans back-end applicatif, sans état
à sauvegarder. 53 pages Markdown compilées par Astro, servies par Nginx dans un
conteneur.

La chaîne complète, de bout en bout :

```
git push main
   └─> GitHub Actions (image.yml) construit l'image Docker
        └─> publie sur ghcr.io/jimmymrti/preventioncambriolage:latest
             └─> le VPS interroge le registre toutes les 10 min (timer systemd)
                  └─> si l'empreinte a changé : docker compose pull + up -d
```

**Le déploiement est en mode « pull ».** C'est le choix structurant de
l'existant : GitHub n'a aucun accès à la machine, aucun port entrant n'est
ouvert pour le déploiement, aucune clé SSH n'est confiée à un tiers. Un compte
GitHub compromis permet de publier une mauvaise image, pas de prendre la main
sur le serveur.

Sur le VPS tournent exactement deux conteneurs :

| Conteneur | Image | Exposition | Rôle |
|---|---|---|---|
| `caddy` | `caddy:2.8-alpine` | 80/tcp, 443/tcp, 443/udp | terminaison TLS, ACME, HSTS |
| `web` | `ghcr.io/.../preventioncambriolage:latest` | aucune (réseau interne `site`) | Nginx 1.27-alpine, HTTP simple sur 8080 |

Le serveur n'héberge ni Node, ni les sources, ni la moindre chaîne de
compilation : uniquement Docker et trois fichiers de configuration.

---

## 2. Arborescence de production sur le VPS

Tout vit dans `/opt/preventioncambriolage` :

```
/opt/preventioncambriolage/
├── docker-compose.prod.yml     copié depuis le dépôt
├── docker/Caddyfile            copié depuis le dépôt
├── maj.sh                      copié depuis le dépôt, chmod +x
├── .env                        créé à la main sur le VPS, chmod 600
└── .docker/                    chmod 700, identifiants ghcr (jeton read:packages)
    └── config.json
```

Plus deux unités systemd dans `/etc/systemd/system/` : `maj-site.service` et
`maj-site.timer`.

Volumes Docker nommés : `caddy_data` (les certificats — **à ne jamais
supprimer**) et `caddy_config`.

> Le dépôt n'est pas cloné sur le VPS. Les fichiers y sont déposés par `scp`.
> C'est précisément ce qu'un socle infra as code doit remplacer.

---

## 3. Build et chaîne d'intégration

### Dockerfile (multi-étapes)

1. **deps** — `node:22-alpine`, `npm ci` isolé pour que le cache npm ne soit
   invalidé que sur changement de `package-lock.json`.
2. **build** — `npm run build` (Astro 5.13), puis précompression `gzip -9 -k`
   des fichiers > 1 ko.
3. **runtime** — `nginx:1.27-alpine`, `USER nginx`, écoute 8080, healthcheck
   `wget --spider` toutes les 30 s. Aucun certificat dans le conteneur.

### Variables injectées **au build** (ce sont des `ARG`, pas des variables d'exécution)

| Variable | Défaut | Effet |
|---|---|---|
| `SITE_URL` | `http://localhost:8080` | canonical, sitemap, JSON-LD, Open Graph |
| `PUBLIC_INDEXABLE` | `0` | `0` = robots.txt interdit tout + `noindex` sur chaque page |
| `PUBLIC_GA_ID` | vide | renseigné = active la mesure d'audience **et** le bandeau de consentement |
| `PUBLIC_CONSENT_APERCU` | `0` | aperçu du bandeau sans traceur, essais uniquement |

**Conséquence à retenir :** changer l'URL du site ou l'ouvrir à l'indexation
impose de reconstruire l'image. Ce n'est pas un réglage serveur.

### Workflows GitHub Actions

| Fichier | Déclencheur | Rôle |
|---|---|---|
| `image.yml` | push sur `main` (hors `docs/`, `images/`, `reports/`, `*.md`), `workflow_dispatch`, `workflow_call` | construit et publie l'image sur ghcr.io, cache `type=gha` |
| `controle.yml` | `pull_request` | `make check`, puis fusion automatique des branches `redaction/*` sous trois gardes, puis appel de `image.yml` |
| `liens-affilies.yml` | cron `0 7 1 * *` | vérifie les liens d'affiliation (demande Internet) |
| `veille-faits-divers.yml` | cron `0 7 1 1,4,7,10 *` | veille presse trimestrielle, résultat interne, rien n'est écrit dans le dépôt |

`make check` = build Astro + contrôle des liens internes + contrôles SEO +
grille de veille hors ligne + `docker compose config --quiet`.

> Les deux workflows planifiés sont exactement le genre de tâche que n8n
> pourrait reprendre. À trancher dans le fil n8n : les laisser sur GitHub
> Actions (gratuit, isolé, sans état à garder) ou les rapatrier sur le VPS
> (plus de maîtrise, mais une dépendance et une surface de plus).

---

## 4. Domaine, DNS et TLS

- **Domaine :** `preventioncambriolage.fr`. Deux enregistrements attendus :
  `A @` vers l'IPv4 du VPS, `AAAA @` vers l'IPv6 si elle existe.
- **`www` n'est pas servi.** Le bloc `www.{$DOMAIN}` du `Caddyfile` est en
  commentaire, à décommenter si l'enregistrement DNS est créé.
- **Certificats :** Caddy, ACME **HTTP-01**, donc le **port 80 doit rester
  ouvert en permanence** — il ne sert pas qu'à rediriger, il porte aussi chaque
  renouvellement. Renouvellement automatique à 30 jours de l'expiration,
  vérification deux fois par jour, aucun cron à prévoir.
- **Contact ACME :** `contact@preventioncambriolage.fr`.
- **HSTS :** posé par Caddy au point de terminaison TLS, avec `preload`.
  Nginx en pose un aussi, mais **conditionnellement** (`map $real_scheme`) :
  rien en HTTP, pour ne pas verrouiller `localhost` dans le navigateur du
  développeur.
- **Quota Let's Encrypt :** 5 certificats identiques par semaine. Un
  `acme_ca` de test est prévu en commentaire dans le `Caddyfile`. **Point
  d'attention direct pour la suite :** ajouter n8n et l'annuaire veut dire de
  nouveaux sous-domaines, donc de nouvelles demandes de certificat. Les essais
  se font sur le ACME de test, pas en production.

Le site n'a **pas pu être interrogé depuis cet environnement** (la politique
réseau sortante bloque l'hôte). L'état réel en production — certificat, en-têtes
servis, valeur de `PUBLIC_INDEXABLE` — reste donc à confirmer côté VPS.

Les mentions légales du site désignent **OVH SAS** comme hébergeur, avec la
mention explicite d'un serveur privé virtuel. L'anonymat de l'éditeur est un
choix assumé et documenté (LCEN art. 6 III 2 et 1er-1) : les éléments
d'identification sont chez l'hébergeur, pas sur le site.

---

## 5. Secrets et variables — où ils vivent aujourd'hui

| Élément | Emplacement | Nature |
|---|---|---|
| `SITE_URL`, `PUBLIC_INDEXABLE`, `PUBLIC_GA_ID` | GitHub → *Settings → Secrets and variables → Actions → **Variables*** | variables, pas des secrets |
| `GITHUB_TOKEN` | fourni automatiquement par Actions | jeton éphémère, `packages: write` |
| `IMAGE`, `DOMAIN`, `ACME_EMAIL` | `/opt/preventioncambriolage/.env`, `chmod 600` | configuration serveur |
| Jeton ghcr en lecture | `/opt/preventioncambriolage/.docker/config.json`, dossier `chmod 700` | PAT classique, **une seule case : `read:packages`** |

**Le détail qui coûte une soirée si on l'ignore :** le service de mise à jour
tourne en root et son durcissement systemd masque `/home` **et** `/root`. Un
`docker login` ordinaire écrirait dans le dossier personnel de l'utilisateur, où
root ne trouverait rien — d'où `Environment=DOCKER_CONFIG=/opt/preventioncambriolage/.docker`
dans l'unité. Toute reprise en IaC doit conserver ce couple
« identifiants dans le dossier de déploiement + variable explicite ».

Aucun secret n'est stocké dans le dépôt. Il n'y a **aucun secret applicatif** :
le site ne parle à personne. Ce ne sera plus vrai avec n8n.

---

## 6. Posture de sécurité déjà en place

Elle est documentée pas à pas dans `docs/vps.md` du dépôt d'origine, et elle est
plus avancée que la moyenne. C'est le socle à reprendre, pas à refaire.

**Système**
- SSH par clé uniquement (`/etc/ssh/sshd_config.d/99-durcissement.conf`) :
  `PasswordAuthentication no`, `KbdInteractiveAuthentication no`,
  `PermitRootLogin no`, `MaxAuthTries 3`, `LoginGraceTime 20`,
  `X11Forwarding no`, `AllowAgentForwarding no`, `AllowTcpForwarding no`.
- UFW : `deny incoming` / `allow outgoing`, trois ouvertures seulement —
  OpenSSH, 80/tcp, 443/tcp + 443/udp.
- fail2ban, jail `sshd`, `bantime 1h`, `findtime 10m`, `maxretry 5`, backend
  systemd.
- `unattended-upgrades` avec redémarrage automatique à 04h30 si un correctif
  l'exige.
- Docker installé depuis le dépôt officiel Docker, pas celui d'Ubuntu.

**Conteneurs** (`docker-compose.prod.yml`)
- `web` : `read_only: true`, `tmpfs` sur `/tmp` et `/var/cache/nginx`,
  `cap_drop: ALL`, `no-new-privileges:true`, aucun port publié.
- `caddy` : `no-new-privileges:true`.
- Rotation des logs sur tous les services : `json-file`, 10 Mo × 3.

**Unité systemd `maj-site.service`**
`NoNewPrivileges`, `PrivateTmp`, `ProtectSystem=strict`,
`ReadWritePaths=/opt/preventioncambriolage`, `ProtectHome`,
`ProtectKernelTunables`, `ProtectKernelModules`, `ProtectControlGroups`,
`RestrictSUIDSGID`.

**Application** (`docker/nginx.conf`)
- CSP stricte : `default-src 'self'`, `script-src 'self' + googletagmanager`,
  `frame-ancestors 'none'`, `object-src 'none'`, aucun script en ligne autorisé
  — y compris les nôtres, d'où le bandeau de consentement servi comme fichier
  depuis `/js/`.
- `X-Content-Type-Options`, `Referrer-Policy`, `Permissions-Policy`,
  `Cross-Origin-Opener-Policy`, `server_tokens off`.
- `set_real_ip_from` sur les plages Docker privées + `X-Forwarded-For`.
- Aucun traceur avant consentement : les scripts Google sont écrits en
  `type="text/plain"` et ne partent pas tant que l'accord n'est pas donné.

### Écarts connus, assumés dans l'existant

Ce sont les points que le chantier ANSSI devra reprendre ou re-justifier :

1. **L'appartenance au groupe `docker` équivaut à root.** Le mode rootless
   existe, il a été écarté parce qu'il complique les ports privilégiés.
2. **Docker contourne UFW.** Un conteneur qui publie un port l'ouvre
   directement dans iptables, sans passer par les règles. La pile actuelle s'en
   protège en ne publiant que 80 et 443, tenus par Caddy. **C'est le piège
   numéro un pour n8n et l'annuaire.**
3. **Aucune supervision.** Rien ne prévient si le site tombe.
4. **Aucune sauvegarde**, et c'était cohérent : tout se reconstruit depuis
   GitHub, seul `caddy_data` a de la valeur et Caddy sait le redemander.
   **Cette hypothèse tombe** dès qu'arrivent n8n (base Postgres, credentials
   chiffrés, historiques d'exécution) et l'annuaire (base de données métier).
5. **Aucune protection contre le déni de service.** La réponse envisagée était
   Cloudflare en mode proxy.
6. Pas de journalisation centralisée, pas d'audit système (`auditd`), pas de
   MAC (AppArmor/SELinux) explicitement configuré, pas de contrôle d'intégrité.

> Références ANSSI à confronter dans le fil « socle » : ANSSI-BP-028
> (recommandations de sécurité relatives à un système GNU/Linux) et la note
> technique sur l'usage sécurisé d'(Open)SSH. Les numéros et versions exacts
> sont à vérifier à la source avant d'être cités dans le dépôt.

---

## 7. Contraintes dures pour la suite

Ce qui casse si on l'ignore.

1. **Les ports 80 et 443 sont tenus par Caddy, et par lui seul.** Tout nouveau
   service passe derrière ce reverse proxy. Pas de second proxy, pas de port
   publié en plus. C'est aussi ce qui garde UFW pertinent.
2. **`caddy_data` doit survivre.** Jamais de `docker compose down -v`.
3. **Le port 80 reste ouvert**, pour ACME.
4. **Le site n'a aucune redirection, par choix.** Une URL absente est une vraie
   404, et `check-links` en CI est le garde-fou qui remplace une table de
   redirections. Une reprise d'URL au niveau du proxy trahirait ce choix : à
   discuter avec Jim avant, pas après.
5. **La CSP est stricte et le restera.** Ajouter un outil tiers (l'annuaire en
   ajoutera) impose d'étendre la politique consciemment, service par service.
   L'annuaire aura vraisemblablement sa propre CSP, plus large : raison de plus
   pour qu'il vive sur son propre domaine ou sous-domaine, pas sous
   `preventioncambriolage.fr`.
6. **Consentement avant traceur, sans exception.** Le lien est fait par
   construction dans le code : un seul réglage commande le bandeau et Google
   Analytics, il est impossible d'avoir l'un sans l'autre.
7. **`SITE_URL` est un `ARG` de build.** Pas modifiable à chaud.
8. **Le nom de compte doit être en minuscules** dans `IMAGE`
   (`ghcr.io/jimmymrti/...`), sinon `invalid reference format`.
9. **Le dépôt d'images est privé**, donc le VPS a besoin de son jeton
   `read:packages` — et root doit pouvoir le lire (voir §5).
10. **Ressources.** Le site consomme très peu : deux conteneurs Alpine, du
    statique. n8n (Node + Postgres + workers) et l'annuaire (application +
    base) changent complètement le profil. Le dimensionnement du VPS est une
    question ouverte, voir §9.

---

## 8. Ce que le VPS doit reprendre, et ce qui doit évoluer

| Élément | Reprendre tel quel | Doit évoluer |
|---|---|---|
| Déploiement en pull (timer + registre) | ✅ modèle à généraliser aux nouveaux services | le script `maj.sh` est mono-service, à généraliser |
| Caddy comme unique point d'entrée TLS | ✅ | configuration multi-sites, un bloc par domaine |
| Durcissement SSH / UFW / fail2ban / MAJ auto | ✅ | à décrire en IaC plutôt qu'en procédure manuelle |
| Durcissement conteneur (`read_only`, `cap_drop`) | ✅ modèle | n8n a besoin d'écrire : `read_only` ne s'appliquera pas tel quel |
| `/opt/<service>` + `.env` 600 | ✅ convention | une arborescence par service, ou un dossier unique multi-piles |
| Fichiers déposés par `scp` | ❌ | c'est ce que l'IaC remplace |
| Absence de sauvegarde | ❌ | obligatoire dès n8n et l'annuaire |
| Absence de supervision | ❌ | à ajouter, au moins une sonde externe |
| Réseau Docker unique `site` | ❌ | un réseau par pile, plus un réseau d'exposition partagé avec Caddy |
| Gestion des secrets | partiellement | un `.env` 600 suffisait pour trois lignes ; n8n impose une vraie clé de chiffrement et des credentials |

---

## 9. Ce qu'il faut demander à Jim

Rien de tout cela n'est dans le dépôt :

1. **Caractéristiques du VPS** : gamme OVH, vCPU, RAM, disque, version d'Ubuntu,
   IPv6 disponible ou non. Détermine si n8n + annuaire + site tiennent sur la
   machine actuelle.
2. **Où est géré le DNS** de `preventioncambriolage.fr` (OVH ou ailleurs), et
   s'il existe un accès API pour automatiser les enregistrements.
3. **Noms retenus** pour n8n et pour l'annuaire : sous-domaines de
   `preventioncambriolage.fr`, ou domaines distincts ? La réponse conditionne
   le découpage des certificats, la CSP et l'isolation.
4. **État réel de la production** : `PUBLIC_INDEXABLE` est-il à `1` ? Le
   `www` est-il déclaré ? Y a-t-il déjà des choses installées sur le VPS hors
   de cette pile ?
5. **Nature de l'annuaire artisans** : volumétrie attendue, base de données
   souhaitée, données à caractère personnel d'artisans (donc RGPD, donc
   sauvegarde et durée de conservation).
6. **n8n** : usage personnel ou exposé à des tiers, besoin SMTP, et jusqu'où on
   accepte qu'il parle à l'extérieur.
7. **Sauvegarde** : option Backup OVH, snapshot, ou sauvegarde applicative vers
   un stockage objet ?

---

## 10. Fichiers de référence dans le dépôt d'origine

| Fichier | Ce qu'il contient |
|---|---|
| `docs/vps.md` | installation et durcissement du VPS, 13 étapes, de la première connexion au site en ligne |
| `docs/deploiement.md` | les deux modes de déploiement, consentement, CSP, diagnostic |
| `docker-compose.prod.yml` | la pile réellement déployée |
| `docker/Caddyfile` | terminaison TLS, HSTS, bloc `www` commenté |
| `docker/nginx.conf` | en-têtes de sécurité, CSP, cache, real_ip |
| `Dockerfile` | build multi-étapes, `ARG` du build |
| `deploiement/maj.sh` + unités systemd | la mise à jour en pull et son durcissement |
| `.github/workflows/image.yml` | construction et publication de l'image |
| `.env.example` | toutes les variables attendues, commentées |
