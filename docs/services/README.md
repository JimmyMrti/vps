# Services applicatifs

Ce dossier décrit **ce qui tourne sur le VPS**, par opposition au socle
(provisionnement, durcissement de l'hôte, frontal Caddy) décrit ailleurs dans
ce dépôt.

| Service | Rôle | Domaine | État |
|---|---|---|---|
| `site` | preventioncambriolage.fr, pages statiques | `preventioncambriolage.fr` | en production |
| `n8n` | automatisation | **aucun — non exposé, accès par tunnel SSH** | à installer |
| `annuaire` | annuaire artisans enrichi | domaine propre, à choisir | à écrire |

| Document | Contenu |
|---|---|
| [`n8n.md`](n8n.md) | exposition, authentification, ce qu'on interdit à n8n |
| [`annuaire.md`](annuaire.md) | contrat d'exécution de l'application, base de données, recherche |
| [`dimensionnement.md`](dimensionnement.md) | mémoire, CPU, disque, limites par conteneur |
| [`sauvegardes.md`](sauvegardes.md) | quoi, où, à quelle fréquence, et comment on vérifie |
| [`donnees-personnelles.md`](donnees-personnelles.md) | ce qui entre dans la base et ce qui n'y entre pas, base légale, provenance, droits des personnes |
| [`registre-traitements.md`](registre-traitements.md) | le registre, à relire à chaque évolution fonctionnelle |

---

## Le principe de cloisonnement

Trois services sur une seule machine, c'est trois occasions de se compromettre
l'un l'autre. La règle tenue ici est simple : **deux conteneurs ne se parlent
que si on l'a écrit quelque part.**

```
                  Internet
                     │
              ┌──────┴──────┐        seul conteneur qui publie 80/443
              │    Caddy    │
              └──────┬──────┘
          réseau ────┼───────────┐  (edge)
                     │           │
             ┌───────┴──┐   ┌────┴─────┐          ┌─────────┐
             │   site   │   │ annuaire │          │   n8n   │──→ Internet
             └──────────┘   └────┬─────┘          └────┬────┘   (sortant seul,
                                 │                     │         réseau à lui)
                      réseau ────┤          réseau ────┤
                                 │                     │
                          ┌──────┴─────┐        ┌──────┴───┐
                          │  postgres  │        │ postgres │
                          │  annuaire  │        │   n8n    │
                          └────────────┘        └──────────┘
                           (internal: true)      (internal: true)

    n8n n'est raccordé à aucun réseau partagé : il ne peut joindre ni le
    site, ni l'annuaire, ni leurs bases. L'accès à son interface passe par
    un tunnel SSH, son port n'étant publié que sur 127.0.0.1.
```

Ce que le schéma impose :

- **Aucun service applicatif ne publie de port.** Sur ce VPS, un `ports:` dans
  un compose ouvre le pare-feu sans passer par UFW — Docker écrit directement
  dans iptables. Le frontal est le seul à avoir le droit de le faire.
- **Chaque base de données vit sur un réseau `internal: true`**, donc sans
  route vers Internet. Une base compromise ne peut pas exfiltrer d'elle-même.
- **Une base par service, pas une base mutualisée.** n8n stocke des
  identifiants d'API chiffrés ; l'annuaire stocke des données de personnes.
  Deux instances PostgreSQL coûtent environ 150 Mo de plus que deux bases dans
  une seule instance — c'est le prix d'un cloisonnement qui tient même si
  quelqu'un obtient le rôle superutilisateur d'un côté.
- **n8n n'est pas exposé du tout.** Il détient les jetons d'accès de tout ce
  qu'il pilote ; l'exposer ne servirait qu'à recevoir des appels entrants, ce
  dont aucun workflow n'a besoin pour l'instant. L'accès à son interface passe
  par un tunnel SSH. Voir [`n8n.md`](n8n.md).
- **n8n reste le seul service qui a une bonne raison d'appeler l'extérieur**,
  et celui qui exécute du code fourni par l'utilisateur : il est traité comme
  le maillon le plus fragile de la chaîne, même sans surface publique.

---

## Contrat avec le socle

**Ce que le socle fournit**, et dont ces fichiers dépendent :

| Élément | Où |
|---|---|
| le réseau Docker externe `edge` | rôle `docker` du socle |
| le frontal Caddy, son `import /etc/caddy/sites/*.caddy`, l'extrait `tls_anssi` et le dossier `sites/` monté en lecture seule | rôle `proxy` |
| `/var/log/caddy` monté depuis l'hôte | rôle `proxy` — l'extrait `journal_acces` y écrit, fail2ban le lit |
| le jeton du registre, dans `/etc/docker/identifiants/config.json` | rôle `docker` — emplacement imposé par le durcissement systemd, qui masque `/home` et `/root` |
| le tunnel SSH autorisé vers `127.0.0.1:5678` et rien d'autre | rôle `ssh` (`AllowTcpForwarding local` + `PermitOpen`) |
| `net.ipv4.conf.all.route_localnet` à 0, relais Docker laissé actif | rôle `socle` — les deux vont ensemble : c'est ce qui rend le port de n8n joignable depuis la machine **seulement** |
| le rôle `maj_service`, qui pose un `maj.sh`, un service et un timer | à appeler avec `maj_nom`, `maj_dossier`, `maj_image`, `maj_intervalle`, `maj_description` |

**Ce que ces fichiers apportent eux-mêmes**, le socle ne l'imposant pas :

| Élément | Convention retenue ici |
|---|---|
| Arborescence | `/opt/vps/services/<nom>/` — `docker-compose.yml` en 0644 root:root, `.env` en 0600 root:root. Le socle, lui, utilise `/opt/vps/frontal/` et `/opt/vps/site/`. |
| Secrets | des fichiers sous `/opt/vps/secrets/<nom>/`, 0600 root:root, jamais dans le compose |
| Mise à jour | voir plus bas : ni n8n ni l'annuaire ne peuvent rider le timer générique tel quel |

---

## Migration à prévoir sur le site existant

> **La machine ne correspond plus à sa procédure.** Le frontal en service
> charge ses fichiers depuis `/srv/proxy/sites/`, chemin absent de ce dépôt, et
> le contenu de son fichier de site n'est pas connu. Ce qui suit décrit la
> bascule telle qu'elle était prévue au vu de la documentation ; **elle est à
> confronter à l'état réel avant d'être déroulée**, et une partie en a
> peut-être déjà été faite autrement.

La procédure documentée décrit un `docker-compose.prod.yml` qui embarque son
propre Caddy et publie 80, 443 et 443/udp. Avec un frontal mutualisé, **les
deux se disputeraient les ports**. La bascule :

1. Créer le réseau `edge` et démarrer le Caddy du socle avec, dans ses sites,
   `preventioncambriolage.caddy` (fourni ici).
2. Retirer le service `caddy` de la pile du site et raccorder `web` au réseau
   `edge` — le site continue d'écouter en HTTP simple sur 8080, sans port
   publié, exactement comme aujourd'hui côté conteneur.
3. Reprendre le volume `caddy_data` existant, ou laisser Caddy redemander les
   certificats. Let's Encrypt limite à **5 certificats identiques par semaine**
   : on ne recommence pas cette étape à volonté.

L'ordre compte : tant que l'ancien Caddy tient les ports, le nouveau ne
démarre pas.

---

## Mise en service, dans l'ordre

L'ordre n'est pas indicatif : chaque étape suppose la précédente.

```bash
# 1. Le socle, d'abord : hôte durci, Docker, réseau `edge`, frontal Caddy.
docker network create edge

# 2. Les enregistrements DNS, AVANT le premier démarrage de Caddy sur un
#    nouveau domaine. Caddy demande le certificat immédiatement, et un DNS qui
#    ne résout pas encore fait échouer la demande.

# 3. Les secrets, jamais dans le dépôt.
install -d -m 0700 -o root -g root /opt/vps/secrets/n8n
openssl rand -hex 32 > /opt/vps/secrets/n8n/mdp_postgres
printf 'N8N_ENCRYPTION_KEY=%s\n' "$(openssl rand -hex 32)" \
  > /opt/vps/secrets/n8n/chiffrement.env
chmod 600 /opt/vps/secrets/n8n/*

# 4. La clé de chiffrement n8n est recopiée dans un gestionnaire de mots de
#    passe, hors du serveur. Sans elle, les sauvegardes de n8n ne valent rien.

# 5. La configuration.
cp services/n8n/.env.example /opt/vps/services/n8n/.env
chmod 600 /opt/vps/services/n8n/.env
#    Puis on renseigne N8N_IMAGE avec une version explicite et N8N_DOMAIN.

# 6. Le démarrage.
docker compose -f /opt/vps/services/n8n/docker-compose.yml up -d

# 7. La première connexion crée le compte propriétaire. Activer la double
#    authentification immédiatement : entre le démarrage et cette étape,
#    n'importe qui atteignant l'interface peut créer ce compte.

# 8. Le dépôt privé des workflows, et le jeton qui l'alimente. Jeton GitHub à
#    portée fine : écriture sur ce seul dépôt, aucun droit ailleurs — surtout
#    pas sur le dépôt d'infrastructure, dont dépend la reconstruction.
git clone <dépôt privé des workflows> /var/sauvegardes/workflows-n8n
printf 'GIT_ASKPASS=\nGITHUB_TOKEN=...\n' \
  > /opt/vps/secrets/sauvegarde/github.env
chmod 600 /opt/vps/secrets/sauvegarde/github.env

# 9. Les sauvegardes, avant de saisir quoi que ce soit qu'on regretterait de
#    perdre.
systemctl enable --now sauvegarde.timer verification-sauvegarde.timer \
                       restauration-test.timer surveillance-disque.timer \
                       export-workflows-n8n.timer

# 10. Pour l'annuaire seulement, la mise à jour automatique — posée par le
#     rôle `maj_service` du socle. Pas pour n8n : voir « Mises à jour ».
systemctl enable --now maj-annuaire.timer
```

L'étape 7 est celle qu'on oublie. Un n8n fraîchement démarré et joignable
attend que quelqu'un crée le compte propriétaire — **le premier qui arrive
l'obtient.** C'est la raison pour laquelle l'interface est fermée par défaut
dans `edge/sites/n8n.caddy` : même pendant ces quelques minutes, il n'y a pas
de fenêtre.

Pour l'annuaire, l'ordre est le même, avec la migration de schéma intercalée :

```bash
docker compose --profile migration run --rm migration
docker compose up -d
```

---

## Mises à jour : pourquoi les deux services ne suivent pas la même règle

Le socle fournit un rôle `maj_service` qui pose, pour un service donné, un
script de mise à jour, une unité systemd et un minuteur : le serveur va
chercher sa nouvelle image, personne ne pousse vers lui. C'est le modèle en
place pour le site statique, et il est bon.

**Ni n8n ni l'annuaire ne peuvent l'utiliser tel quel**, pour deux raisons
différentes.

### n8n : jamais de mise à jour automatique

Une montée de version majeure de n8n **migre sa base au démarrage**, et cette
migration ne se défait pas. Un minuteur qui tire `latest` transformerait une
publication amont en modification irréversible de vos données, une nuit, sans
que personne l'ait décidé.

D'où l'image fixée à une version explicite dans `.env`. La mise à jour est un
geste conscient :

```bash
# 1. Sauvegarder d'abord — c'est le moment où ça compte le plus.
systemctl start sauvegarde.service

# 2. Lire les notes de version, en particulier les changements de rupture.
# 3. Relever N8N_IMAGE dans /opt/vps/services/n8n/.env
# 4. Appliquer.
docker compose -f /opt/vps/services/n8n/docker-compose.yml up -d
```

Le retour arrière n'est pas garanti : si la migration a modifié le schéma,
redescendre de version demande de restaurer la base. C'est précisément
pourquoi l'étape 1 n'est pas facultative.

### L'annuaire : mise à jour automatique, avec les migrations

L'annuaire est notre code, publié en continu : le modèle « pull » lui va, et
il utilise le rôle `maj_service` du socle.

Le script générique faisait `pull` puis `up -d`, ce qui aurait démarré du code
neuf sur une base restée en arrière. Le socle a ajouté un crochet
`maj_commande_avant`, joué entre le téléchargement et le démarrage, et
seulement si l'image a changé. L'annuaire s'y branche :

```yaml
maj_nom: annuaire
maj_dossier: /opt/vps/services/annuaire
maj_compose_service: annuaire
maj_intervalle: 10min
maj_commande_avant: "docker compose --profile migration run --rm migration"
```

`set -e` étant actif dans le script, une migration qui échoue arrête tout
**avant** le redémarrage : l'ancienne version continue de tourner sur une base
intacte, et l'unité systemd apparaît en échec. C'est le bon comportement.

`maj_compose_service` désigne le service à suivre — ici `annuaire`, pas `web` :
la pile en contient plusieurs (l'application, sa base, le conteneur de
migration), et sans cette désignation le script ne saurait pas laquelle des
images surveiller.

L'étiquette de l'image n'est déclarée qu'à un seul endroit, `ANNUAIRE_IMAGE`
dans `.env` : le script la lit depuis la pile elle-même. C'est ce qui évite la
panne la plus vicieuse du genre — deux déclarations qui divergent, un script
qui ne voit jamais de changement, et un service qui reste des semaines sur
l'ancienne version sans que rien ne le signale.
