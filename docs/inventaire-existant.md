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
- **`www` résout, mais n'est pas servi. C'est un défaut en production.**
  Vérifié le 21 septembre 2026 : `www.preventioncambriolage.fr` répond en
  `92.222.91.185` et `2001:41d0:404:200::5baf`, exactement comme le domaine nu.
  Or le bloc `www.{$DOMAIN}` du `Caddyfile` est en commentaire. Caddy n'a donc
  aucun certificat pour ce nom et aucun site à lui servir : un visiteur qui tape
  `www.` obtient un avertissement de sécurité du navigateur, pas une
  redirection. Décommenter ce bloc est un correctif d'une ligne.
  Au passage, la machine a bien une IPv6.
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
    base) changent complètement le profil. La machine a de la marge — 4 vCores
    et 8 Go — mais 75 Go de disque se remplissent plus vite qu'on ne croit.
    Voir §9.

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

## 9. La machine et le contexte, tels que Jim les a donnés

Répondu le 21 septembre 2026.

### La machine

**VPS 2 chez OVH : 4 vCores, 8 Go de RAM, 75 Go de stockage, Ubuntu 26.04.**

C'est confortable pour les trois services. Le site statique ne consomme
quasiment rien — deux conteneurs Alpine servant des fichiers. n8n avec sa base
Postgres demande de l'ordre du gigaoctet, l'annuaire et sa base autant ou un peu
plus selon la technologie retenue. La marge est réelle.

**Le point de tension sera le disque, pas la mémoire.** 75 Go se remplissent
avec les images Docker successives, la base de l'annuaire, ses médias, et
surtout l'historique d'exécution de n8n, qui grossit indéfiniment si on ne le
purge pas (n8n sait le faire, le réglage est à relever dans sa documentation).
La purge des images de plus d'une semaine est déjà faite par `maj.sh`, et la
rotation des logs est déjà en place sur tous les services : deux réflexes à
conserver et à étendre aux nouvelles piles.

**Ubuntu 26.04 — un point à vérifier avant de dérouler quoi que ce soit.** La
procédure d'origine installe Docker depuis le dépôt officiel, en dérivant le nom
de code de la distribution (`$VERSION_CODENAME`). Docker publie parfois avec du
retard pour une version fraîchement sortie. Si le dépôt ne répond pas pour
26.04, il faut épingler explicitement le nom de code de la version précédente
plutôt que de se rabattre sur le paquet d'Ubuntu, qui est en retard.

### Le DNS

**Il est chez OVH**, comme le VPS. Deux conséquences directes :

1. Les enregistrements sont **automatisables** via l'API OVH, avec un jeton à
   portée restreinte (`/domain/zone/*`). Le DNS peut donc entrer dans l'infra as
   code au lieu d'être cliqué dans une interface.
2. Le challenge ACME **DNS-01 devient possible**, là où l'existant fait du
   HTTP-01. Il permet des certificats *wildcard* et supprime le besoin de garder
   le port 80 joignable pour chaque renouvellement.

   Le prix à payer : l'image officielle de Caddy ne contient pas le module DNS
   d'OVH. Il faut construire une image avec `xcaddy`, donc maintenir une image
   de plus et suivre ses mises à jour de sécurité. **Arbitrage pour le fil
   socle**, pas une évidence : HTTP-01 fonctionne déjà, et le port 80 doit de
   toute façon rester ouvert pour la redirection.

### Les noms de domaine

Jim a tranché : **aucun sous-domaine de `preventioncambriolage.fr`**, chaque
service sur son propre domaine (voir §9 bis). Les deux éléments ci-dessous sont
ce qui a conduit à cette décision ; ils sont conservés parce qu'ils expliquent
pourquoi elle est la bonne.

**L'en-tête HSTS actuel porte `includeSubDomains; preload`.** Tout sous-domaine
de `preventioncambriolage.fr` devra donc être servi en HTTPS, sans exception et
sans période de transition — un navigateur qui a vu l'en-tête refusera le HTTP
sur `n8n.preventioncambriolage.fr` avant même d'avoir essayé. Ce n'est pas
bloquant, tout passera par Caddy de toute façon, mais cela interdit définitivement
le moindre service en clair, y compris temporaire, y compris pour un essai.
*À vérifier :* le domaine est-il réellement soumis à la liste de préchargement
des navigateurs, ou l'en-tête porte-t-il seulement la directive ? Dans le
premier cas, la décision est irréversible à l'échelle de plusieurs mois.

**L'anonymat de l'éditeur est un choix assumé et documenté** dans les mentions
légales. Un sous-domaine apparaît en clair dans les journaux de transparence des
certificats, publics et indexés. `n8n.preventioncambriolage.fr` annoncerait donc
à qui regarde que ce site a un serveur d'automatisation. Ce n'est pas une faille,
mais c'est une information publiée. Un domaine distinct pour l'outillage interne
évite la question ; pour l'annuaire, qui est un produit à part avec ses propres
besoins de CSP et de cookies, un domaine séparé se défend de toute façon.

---

## 9 bis. Décisions prises

Prises par Jim le 21 septembre 2026.

### Chaque service sur son propre domaine

**Aucun sous-domaine de `preventioncambriolage.fr`.** Les trois services sont
séparés, domaine compris.

C'est la décision la plus structurante du lot, et elle simplifie beaucoup de
choses : plus de question de HSTS hérité, des cookies qui ne peuvent pas fuir
d'un service à l'autre, une politique de sécurité de contenu par site sans
compromis, et rien qui relie publiquement l'outillage au site éditorial. Chaque
domaine devient un bloc indépendant dans la configuration de Caddy.

### n8n : le nom du VPS ne peut pas porter de certificat

L'idée d'utiliser le nom par défaut de la machine (`vpsXXXXXX.vps.ovh.net`)
donne bien l'effet recherché — un nom quelconque, sans lien avec le site — mais
elle bute sur trois obstacles, dont le premier est rédhibitoire.

1. **Le quota Let's Encrypt serait partagé avec tous les clients d'OVH.**
   Vérifié le 21 septembre 2026 sur la liste officielle des suffixes publics :
   `vps.ovh.net` n'y figure pas — seuls `*.hosting.ovh.net` et
   `*.webpaas.ovh.net` y sont. Pour Let's Encrypt, le domaine de rattachement
   est donc `ovh.net` tout entier, et le plafond de certificats par domaine
   enregistré est commun à tous ceux qui utilisent leur nom par défaut. On
   n'aurait aucune prise sur un `too many certificates already issued`.
2. **Le challenge DNS-01 est impossible.** La zone `ovh.net` ne nous appartient
   pas : aucun enregistrement TXT à y créer, donc ni wildcard, ni renouvellement
   indépendant du port 80.
3. **Le nom ne nous appartient pas non plus.** Il est attaché à la machine, et
   change si la machine change.

**Recommandation : un domaine distinct, au nom quelconque, quelques euros par an
chez OVH.** Il donne exactement la propriété recherchée, sans aucun des trois
inconvénients, et il rend le DNS-01 possible puisque la zone serait la nôtre.

**Et une question à trancher avant celle du nom :** n8n a-t-il besoin d'être
exposé ? Un serveur d'automatisation détient les jetons d'accès à tout ce qu'il
pilote — c'est la cible la plus intéressante de la machine. Son interface peut
n'être joignable que par un tunnel (WireGuard, ou un simple tunnel SSH), et seuls
les points d'entrée de webhooks, s'il en faut, restent publics.

### Séparer les webhooks de l'interface n8n

C'est faisable, et de deux manières. Relevé dans la documentation de n8n le
21 septembre 2026.

**La voie simple : le proxy trie les chemins.** n8n sert tout depuis le même
port, mais chaque famille d'URL a son préfixe, et ces préfixes sont des réglages
documentés :

| Réglage | Valeur par défaut | Ce qu'il sert |
|---|---|---|
| `N8N_ENDPOINT_WEBHOOK` | `webhook` | les webhooks de production |
| `N8N_ENDPOINT_WEBHOOK_WAIT` | `webhook-waiting` | les reprises de workflows en attente |
| `N8N_ENDPOINT_WEBHOOK_TEST` | `webhook-test` | les webhooks d'essai — **à ne pas exposer** |
| `N8N_ENDPOINT_REST` | `rest` | l'API interne de l'éditeur |
| `N8N_ENDPOINT_HEALTH` | `healthz` | la sonde de santé |

Le domaine public ne laisse donc passer que `/webhook/*` et
`/webhook-waiting/*`, et répond 404 à tout le reste. L'éditeur, son API `rest`
et ses fichiers statiques ne sont joignables que par le tunnel.

**La règle porte sur les chemins d'URL, pas sur les adresses IP.** Aucune adresse
fixe n'est nécessaire, ni côté visiteur, ni côté administrateur : un webhook doit
justement être appelable par n'importe qui. Ce que le proxy filtre, c'est le
début de l'URL demandée.

**Et elle s'écrit en liste blanche**, pas en liste noire : on autorise deux
préfixes, on refuse le reste. Une liste noire oublie toujours un chemin, et
l'oubli ici expose l'éditeur.

`N8N_WEBHOOK_URL` (ou `WEBHOOK_URL`) fixe l'adresse publique que n8n inscrit
dans les URL qu'il distribue aux services tiers : sans lui, il annoncerait
l'adresse privée.

*Un point à vérifier au moment de l'implémentation :* les déclencheurs de type
formulaire servent sur leur propre chemin, qui ne figure pas dans le tableau
ci-dessus. Si le projet en utilise, il faudra l'ajouter à la liste blanche.

**La voie propre : un processus dédié.** En mode file d'attente, n8n sait
démarrer un processus qui ne sert *que* les webhooks — la commande est
`n8n webhook`. La documentation est explicite : ce processus ne sert ni
l'interface, ni l'API interne, ni les fichiers statiques de l'éditeur, qui
doivent être routés vers le processus principal. La séparation n'est plus une
règle de proxy mais deux conteneurs distincts, dont un seul est exposé — et une
erreur de configuration du proxy ne peut plus découvrir l'éditeur.

Le prix : le mode file d'attente réclame une base de données **et** Redis, plus
un processus principal et au moins un worker. Quatre conteneurs au lieu d'un,
pour un usage qui n'a pas de problème de volumétrie. Le réglage
`N8N_DISABLE_PRODUCTION_MAIN_PROCESS` existe pour que le processus principal
cesse alors de servir les webhooks lui-même.

**Recommandation : commencer par la voie simple**, liste blanche de chemins sur
deux préfixes et éditeur derrière le tunnel. Elle donne la même surface d'exposition
publique pour un conteneur au lieu de quatre. Le mode file d'attente se
justifiera si le volume de webhooks l'impose. À instruire dans le fil n8n.

### Joindre l'éditeur n8n depuis une adresse changeante

Garder l'éditeur privé ne demande pas d'adresse IP fixe non plus. Deux moyens,
du plus simple au plus confortable.

**Le tunnel SSH, qui n'ajoute rien.** Le conteneur n8n ne publie son port que sur
la boucle locale de l'hôte — `127.0.0.1:5678:5678` dans le fichier Compose — et
l'administrateur ouvre un tunnel depuis son poste :

```bash
ssh -L 5678:127.0.0.1:5678 ubuntu@le-vps
```

L'éditeur est alors sur `http://localhost:5678` dans son navigateur. Rien de
neuf à installer, rien de neuf à ouvrir au pare-feu : cela réutilise la clé SSH
et le port déjà autorisés. La connexion part du poste vers le serveur, donc
l'adresse du poste n'a aucune importance — elle peut changer à chaque fois, être
celle d'un partage de connexion mobile, peu importe.

**Ce détail de la boucle locale n'est pas cosmétique.** Publier un port de
conteneur sans préciser l'interface l'ouvre directement dans iptables, en
contournant UFW — c'est le piège relevé au §7. Préfixer par `127.0.0.1:` est
exactement ce qui l'évite : le port existe pour l'hôte et pour le tunnel, jamais
pour Internet. Caddy, lui, joint n8n par le réseau interne de Docker pour les
deux chemins de webhooks, sans passer par ce port.

**WireGuard, si le confort l'emporte.** Un tunnel permanent évite de relancer
une commande à chaque fois et couvre d'un coup tous les services internes à
venir. Le poste est client, le VPS serveur : là encore la connexion part du
poste, donc aucune adresse fixe n'est requise. Le prix est un port UDP à ouvrir
au pare-feu et une configuration de plus à tenir.

**Recommandation : le tunnel SSH pour commencer.** Il ajoute zéro surface
d'exposition, ce qui est exactement ce qu'on cherche pour la pièce qui détient
tous les jetons. WireGuard se justifiera le jour où plusieurs services internes
demanderont un accès régulier.

### Sauvegarde : GitHub au maximum, un roulement pour le reste

Le principe retenu prolonge celui du site : **ce qui se reconstruit depuis Git
n'a pas à être sauvegardé**. L'effort porte donc d'abord sur la réduction de ce
qui n'est pas du code.

**Va sur GitHub** : l'infrastructure as code, les configurations, les schémas et
migrations de bases, le contenu éditorial, les jeux de données de référence sans
données personnelles.

**Ne va pas sur GitHub**, et ce point n'est pas négociable :

1. **Les secrets.** Clé de chiffrement de n8n, jetons d'API, mots de passe de
   bases. Un dépôt privé n'est pas un coffre-fort : il est lisible par toute
   personne ayant accès au dépôt, et un secret poussé par erreur reste dans
   l'historique même après suppression du fichier.
2. **Les données personnelles des artisans.** Deux raisons distinctes, et la
   première suffit : l'historique Git est immuable, donc une demande d'effacement
   au titre du RGPD deviendrait impossible à honorer — le commit resterait. La
   seconde est qu'y verser un fichier de données personnelles est un transfert
   vers un tiers, qu'il faudrait pouvoir justifier et documenter.
3. **Les credentials enregistrés dans n8n**, même chiffrés : ils ne valent que
   ce que vaut la clé, et la clé ne doit pas vivre au même endroit.

**D'où deux destinations.** GitHub pour le code. Un stockage à roulement pour
l'état — bases de données, volumes, secrets chiffrés.

Le roulement demandé est exactement ce que font les outils de sauvegarde à
rétention, `restic` ou `borg` : garder tant de sauvegardes quotidiennes, tant
d'hebdomadaires, tant de mensuelles, et purger le reste automatiquement. Ils
chiffrent et dédupliquent au passage, ce qui rend la destination moins sensible.
La destination naturelle est l'Object Storage d'OVH — compatible S3, en France,
même fournisseur, facturé à l'usage — mais n'importe quel S3 convient, et en
choisir un autre qu'OVH met les sauvegardes à l'abri d'un incident chez OVH.

Deux réflexes à ne pas perdre : la clé de chiffrement des sauvegardes ne doit pas
vivre uniquement sur la machine sauvegardée, et **une sauvegarde jamais restaurée
n'est pas une sauvegarde** — la restauration se teste, et l'IaC rend ce test bon
marché.

---

## 9 ter. L'annuaire artisans contiendra des données personnelles

Confirmé par Jim les 21 et 22 septembre 2026 : l'annuaire contiendra des
**données à caractère personnel**, et toute information récupérable en source
ouverte. Une première version sera **mise à l'épreuve sur la seule région
Rhône-Alpes**, et Jim précise que seules les données légalement récoltables
seront intégrées.

Le périmètre régional est une bonne nouvelle pour l'infrastructure : la
volumétrie reste modeste, très loin de la contrainte de disque relevée au §9, et
il laisse le temps d'éprouver la chaîne d'effacement avant de l'appliquer à
l'échelle nationale.

**Une précision utile sur « légalement récoltable ».** C'est le bon réflexe,
mais l'obligation la plus lourde ne porte pas sur la collecte : on peut
collecter licitement et devoir quand même informer chaque personne. Le tri à
l'entrée ne dispense donc pas de ce qui suit.

Ce n'est pas un détail de conformité à traiter à la fin. C'est une contrainte
d'architecture, parce que trois obligations se traduisent directement en code et
en infrastructure.

**Public ne veut pas dire librement réutilisable.** La CNIL est explicite :
des données publiquement accessibles restent des données personnelles, elles
« ne sont pas librement réutilisables par tout responsable de traitement », et
elles ne peuvent pas être exploitées à l'insu de la personne concernée. Il faut
une base légale — l'intérêt légitime, vraisemblablement, et il se documente. La
CNIL ajoute qu'il faut vérifier que les conditions d'utilisation des sites
moissonnés n'interdisent pas la collecte.

Deux précisions de périmètre. Un artisan en nom propre — entreprise
individuelle, micro-entrepreneur — est une personne physique : son nom, son
adresse et son téléphone professionnel sont des données personnelles. Et les
registres publics d'entreprises comportent un statut de diffusion : certains
entrepreneurs individuels se sont opposés à la diffusion de leurs informations.
*À vérifier à la source avant toute collecte*, car republier ces
enregistrements-là serait une faute nette.

### Ce que ça impose au code et à l'infra

1. **L'information des personnes (article 14 du RGPD).** Les données n'étant pas
   collectées auprès de l'artisan, il faut l'informer, et la CNIL précise : au
   plus tard au moment de la première communication, en indiquant la source. Une
   page d'information accessible ne suffit pas toujours, et c'est l'obligation
   la plus lourde d'un annuaire constitué par moisson.
2. **La provenance de chaque donnée doit être stockée.** On ne peut pas indiquer
   la source si le schéma ne la porte pas. C'est une colonne par enregistrement,
   pas une note en bas de page — décision à prendre dès la conception du schéma,
   très coûteuse à rattraper ensuite.
3. **L'effacement doit être réellement possible**, de bout en bout : base,
   caches, index de recherche, exports, **et sauvegardes**. D'où une rétention
   bornée sur les sauvegardes — un roulement qui finit par oublier, ce qui est
   exactement le roulement demandé — et la confirmation de ce qui a été écrit
   plus haut : ces données ne vont pas sur GitHub, dont l'historique est
   immuable.
4. **Un canal d'opposition** et de rectification, avec quelqu'un pour le relever.
   Un annuaire sans adresse de contact fonctionnelle n'est pas tenable.

Ces éléments relèvent de la conception de l'annuaire, pas de l'inventaire. Ils
sont consignés ici parce qu'ils décident de choses que l'infrastructure doit
prévoir dès le départ : un schéma qui porte la provenance, une rétention bornée,
et une chaîne d'effacement qui va jusqu'aux sauvegardes.

> Ce qui précède relève les obligations visibles depuis la documentation de la
> CNIL. Ce n'est pas un avis juridique, et la doctrine de la CNIL sur la
> réutilisation des données publiquement accessibles mérite d'être relue
> directement avant la mise en ligne.

---

## 9 quater. État des questions

**La machine est propre.** Jim l'a confirmé le 22 septembre 2026 : rien n'est
installé sur le VPS en dehors de la pile décrite ici. Le fil socle peut donc
partir d'une base connue, sans inventaire préalable de l'existant.

Avec le `www` traité au §4 et l'indexation déduite du workflow de construction,
il ne reste plus de question ouverte sur la production.

**Restent deux choix de conception**, qui relèvent des fils suivants et non de
cet inventaire :

1. **La technologie de l'annuaire**, qui décidera du dimensionnement de sa base.
   Le périmètre de test sur Rhône-Alpes rend la question peu pressante.
2. **Pour n8n : quelle voie de séparation** — liste blanche de chemins sur le
   proxy, ou processus webhook dédié en mode file d'attente — et **quel tunnel**
   pour l'éditeur. Les deux réponses recommandées sont au §9 bis.


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
