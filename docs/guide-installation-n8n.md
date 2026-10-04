# Guide d'installation sécurisée de n8n sur le VPS

Ce guide installe n8n à la main, commande par commande, sur le VPS tel qu'il
tourne aujourd'hui (voir `docs/etat-reel-vps.md`, PR #6). Il reprend la
configuration écrite dans la PR #2 (`services/n8n/`) et l'adapte à la machine
réelle.

**Ce que vous obtenez à la fin :**

- n8n 2.x et sa base PostgreSQL dédiée, dans `/srv/n8n/` ;
- aucune exposition publique : pas de domaine, pas de certificat, aucun port
  ouvert sur Internet. Le port 5678 n'écoute que sur `127.0.0.1` ;
- l'éditeur joint depuis votre poste Windows par un tunnel SSH, et par rien
  d'autre ;
- une base sans aucune route vers Internet, un n8n qui ne voit ni le site ni
  le frontal Caddy ;
- une procédure de sauvegarde, de restauration et de mise à jour, testée.

**Ce que ce guide ne fait pas :** il n'expose pas de webhook (le jour venu, voir
« Cas 2 » dans `services/n8n/.env.example` et `edge/sites/n8n.caddy` de la
PR #2), et il ne met pas en place les sauvegardes chiffrées hors machine
(`services/_commun/sauvegarde.sh`, PR #2). Il ne touche ni à Caddy ni au site.

Toutes les commandes ont été jouées dans un environnement de test le
4 octobre 2026 avec n8n 2.41.6, PostgreSQL 17 et Docker 29 : démarrage,
isolement réseau, sauvegarde et restauration. Trois corrections à la
configuration de la PR #2 en sont sorties ; elles sont appliquées à l'étape 4
et résumées à la fin.

Conventions :

- `<compte>` est votre compte d'administration sur le VPS, `<vps>` son adresse
  ou son nom, `<clé>` le fichier de votre clé privée sur le poste
  (par exemple `C:\Users\Jim\.ssh\id_ed25519`).
- Les blocs marqués **VPS** se collent dans une session SSH ouverte sur le
  serveur. Les blocs marqués **PowerShell** se collent sur le poste Windows.
- Toujours `sudo docker …`, jamais `docker …` seul : la variable
  `DOCKER_CONFIG` exportée dans votre shell pointe vers un dossier que votre
  compte ne lit pas, ce qui donne des erreurs `unauthorized`. `sudo` ne la
  transmet pas.

---

## Étape 1 — Vérifier la machine avant d'installer

**VPS**

```sh
# 1. SSH : clé obligatoire, mot de passe refusé, tunnel local permis.
sudo sshd -T | grep -E '^(passwordauthentication|authenticationmethods|allowtcpforwarding|permitrootlogin) '
```

Attendu : `passwordauthentication no`, `authenticationmethods publickey`,
`allowtcpforwarding yes` (ou `local`), `permitrootlogin no`. Si
`passwordauthentication` vaut `yes`, corrigez-le d'abord (correction 1 du
relevé privé) : n8n va détenir des jetons d'accès, la porte SSH doit être
fermée avant.

```sh
# 2. Un port publié sur 127.0.0.1 ne doit pas être joignable depuis le réseau.
#    Attendu : 0. À 1, le port de n8n redeviendrait accessible de l'extérieur.
sysctl net.ipv4.conf.all.route_localnet

# 3. Rien n'écoute déjà sur 5678, et /srv/n8n n'existe pas encore.
sudo ss -tlnp | grep ':5678 ' || echo "5678 libre"
ls -d /srv/n8n 2>/dev/null || echo "/srv/n8n absent"

# 4. Place disque : il faut environ 3 Go (image n8n 1,8 Go, PostgreSQL 0,4 Go).
df -h /
```

---

## Étape 2 — Restreindre le tunnel SSH à n8n seul

Aujourd'hui, `AllowTcpForwarding yes` permet à un tunnel de viser n'importe
quelle adresse joignable depuis le serveur, réseaux Docker et futures bases de
données compris, et autorise aussi les tunnels inverses (`-R`). On le limite à
ce dont n8n a besoin : un tunnel local, vers `127.0.0.1:5678` uniquement.
C'est la règle que le socle (PR #3, rôle `ssh`) posera aussi.

**Gardez votre session SSH actuelle ouverte pendant toute cette étape**, et
testez depuis une seconde fenêtre : une erreur ici ne vous enfermera pas
dehors tant que la première session reste ouverte.

**VPS**

```sh
# Le fichier est préfixé 10- pour être lu avant 50-cloud-init.conf et
# 99-hardening.conf : sshd garde la première valeur qu'il lit.
sudo tee /etc/ssh/sshd_config.d/10-tunnel-n8n.conf >/dev/null <<'EOF'
# Tunnel vers l'éditeur n8n : -L seulement, vers 127.0.0.1:5678 seulement.
AllowTcpForwarding local
PermitOpen 127.0.0.1:5678
GatewayPorts no
AllowAgentForwarding no
AllowStreamLocalForwarding no
PermitTunnel no
EOF
sudo chmod 644 /etc/ssh/sshd_config.d/10-tunnel-n8n.conf

sudo sshd -t && sudo systemctl reload ssh
sudo sshd -T | grep -E '^(allowtcpforwarding|permitopen) '
```

Attendu : `allowtcpforwarding local` et `permitopen 127.0.0.1:5678`.

Ouvrez une **seconde** fenêtre PowerShell et vérifiez que vous vous connectez
toujours :

**PowerShell**

```powershell
ssh -i <clé> <compte>@<vps> "echo connexion ok"
```

Si ça échoue, supprimez le fichier depuis la première session
(`sudo rm /etc/ssh/sshd_config.d/10-tunnel-n8n.conf && sudo systemctl reload ssh`).

**Piège :** avec `PermitOpen`, le tunnel doit viser `127.0.0.1:5678`
littéralement. `-L 5678:localhost:5678`, qu'on trouve dans certains
commentaires de la PR #2, sera refusé (`administratively prohibited`).

---

## Étape 3 — Créer l'arborescence et récupérer les fichiers

Les fichiers viennent de la PR #2, figés sur un commit précis et vérifiés par
empreinte : si la branche bouge, ce guide ne change pas de sens.

**VPS**

```sh
sudo install -d -m 0750 -o root -g root /srv/n8n
sudo install -d -m 0700 -o root -g root /srv/n8n/secrets
sudo install -d -m 0700 -o root -g root /srv/n8n/sauvegardes
cd /srv/n8n

C=6546b0233562e08174c3c9dbf3fd1f5576d8bf47
B=https://raw.githubusercontent.com/JimmyMrti/vps/$C/services/n8n
sudo curl -fsSL -o docker-compose.yml "$B/docker-compose.yml"
sudo curl -fsSL -o .env "$B/.env.example"
sudo chmod 600 .env

sha256sum docker-compose.yml .env
```

Les deux empreintes doivent être exactement :

```
1cc20a4009ec72dd08da88c0fb794a3a05e21018fcba319fdcb8f93587c2ceed  docker-compose.yml
17dc335ef030635731dd03bcf7525ff22042b638c7a27ffe06507b0bab2fbfc9  .env
```

Si l'une diffère, arrêtez-vous : le fichier n'est pas celui qui a été testé.

---

## Étape 4 — Adapter la configuration à la machine réelle

Cinq changements, tous issus du test :

1. les chemins : la PR #2 suppose `/opt/vps/`, la machine utilise `/srv/` ;
2. le nœud **Local File Trigger** : n8n 2.x l'interdit par défaut avec
   « Execute Command », mais la PR #2 redéfinit `NODES_EXCLUDE` avec
   Execute Command seul, ce qui le **réautorise**. On rétablit les deux ;
3. PostgreSQL 17 au lieu de 16 : n8n 2.41 signale le 16 comme hors de sa
   plage prise en charge. Installation neuve, donc rien à migrer ;
4. la version de n8n, figée (étape 5) ;
5. deux réglages ajoutés au `.env` : l'écoute IPv4 explicite, et la taille du
   tas JavaScript. Sans ce dernier, Node se limite à environ 270 Mo dans un
   conteneur borné à 1,5 Go, et **n8n 2.x meurt au démarrage**
   (`JavaScript heap out of memory`).

**VPS**

```sh
cd /srv/n8n

sudo sed -i \
  -e 's#/opt/vps/secrets/n8n#/srv/n8n/secrets#g' \
  -e 's#/opt/vps/services/n8n#/srv/n8n#g' \
  -e 's/"n8n-nodes-base.executeCommand"\]/"n8n-nodes-base.executeCommand","n8n-nodes-base.localFileTrigger"]/' \
  -e 's#image: postgres:16-alpine#image: postgres:17-alpine#' \
  docker-compose.yml

sudo tee -a .env >/dev/null <<'EOF'

# --- Ajouts de l'installation (docs/guide-installation-n8n.md) ---
# Écoute IPv4 explicite : n8n refuse de démarrer si '::' n'est pas disponible.
N8N_LISTEN_ADDRESS=0.0.0.0
# Tas JavaScript : sans ce réglage, Node le limite à ~270 Mo dans un conteneur
# borné à 1536 Mo, et n8n 2.x meurt au démarrage faute de mémoire.
NODE_OPTIONS=--max-old-space-size=1024
EOF

# Contrôle : aucune trace de /opt, les deux nœuds exclus, PostgreSQL 17.
grep -n '/opt' docker-compose.yml || echo "plus de /opt"
grep -n 'NODES_EXCLUDE\|postgres:1' docker-compose.yml
```

---

## Étape 5 — Figer la version de n8n

Jamais `latest` : une version majeure migre la base sans retour possible.

Au 4 octobre 2026, la version **stable** est `2.41.6` (la 2.42 est en
préversion, étiquette `next`). Pour vérifier la version stable du jour, ouvrir
<https://hub.docker.com/r/n8nio/n8n/tags?name=stable> et prendre le numéro qui
porte la même empreinte que `stable`.

**VPS**

```sh
cd /srv/n8n
sudo sed -i 's#^N8N_IMAGE=.*#N8N_IMAGE=docker.n8n.io/n8nio/n8n:2.41.6#' .env
sudo grep '^N8N_IMAGE=' .env
```

---

## Étape 6 — Créer les secrets

Deux secrets, créés sur la machine et jamais ailleurs :

- le mot de passe de la base ;
- la **clé de chiffrement** de n8n, qui chiffre tous les identifiants que vous
  enregistrerez. Sans elle, une sauvegarde de n8n est inutilisable ; si elle
  change, tous les identifiants sont à ressaisir.

**VPS**

```sh
cd /srv/n8n/secrets

# Mot de passe de la base, sans retour à la ligne final.
openssl rand -hex 32 | tr -d '\n' | sudo tee mdp_postgres >/dev/null
# Il est lu dans le conteneur par l'utilisateur « node » (uid 1000) de n8n :
# sans ce chown, n8n s'arrête sur « EACCES: permission denied ». Le dossier
# secrets/ reste en 0700 root, donc personne d'autre sur la machine n'y accède.
sudo chown 1000:1000 mdp_postgres
sudo chmod 400 mdp_postgres

# Clé de chiffrement.
printf 'N8N_ENCRYPTION_KEY=%s\n' "$(openssl rand -hex 32)" | sudo tee chiffrement.env >/dev/null
sudo chmod 600 chiffrement.env

sudo ls -la /srv/n8n/secrets
```

**Recopiez maintenant la clé de chiffrement dans votre gestionnaire de mots de
passe**, puis effacez l'écran :

```sh
sudo cat /srv/n8n/secrets/chiffrement.env; read -p "Clé recopiée ? Entrée pour effacer l'écran " _; clear
```

Elle ne va ni dans un dépôt git, ni dans un courriel, ni dans les fichiers du
projet.

---

## Étape 7 — Valider puis démarrer

**VPS**

```sh
cd /srv/n8n

# La configuration se lit sans erreur.
sudo docker compose config --quiet && echo "configuration valide"

# Le seul port publié l'est sur la boucle locale. Attendu : host_ip: 127.0.0.1
sudo docker compose config | grep -B1 -A4 'ports:'

sudo docker compose pull
sudo docker compose up -d
```

n8n met environ une minute à démarrer la première fois (migrations de la
base). Puis :

```sh
sudo docker compose ps
```

Attendu : `n8n-n8n-1` et `n8n-n8n-db-1` à l'état `Up … (healthy)`, et
`127.0.0.1:5678->5678/tcp` dans la colonne des ports de n8n.

Dans les journaux (`sudo docker compose logs n8n --tail 50`), trois messages
sont normaux : `N8N_RUNNERS_ENABLED -> Remove this environment variable`
(réglage devenu inutile en 2.x), `Internal task runner mode is deprecated`,
et `Failed to start Python task runner` (le nœud Code en Python n'est pas
disponible dans cette installation ; le JavaScript l'est).

### Rendre le dossier de fichiers inscriptible

Les nœuds de lecture et d'écriture de fichiers ne voient que `/data/fichiers`.
Docker crée ce volume au nom de root : n8n ne peut pas y écrire tant qu'on ne
le lui donne pas.

```sh
sudo docker run --rm --user root --entrypoint chown \
  -v n8n_n8n_fichiers:/d docker.n8n.io/n8nio/n8n:2.41.6 node:node /d
```

---

## Étape 8 — Vérifier l'isolement

C'est l'étape qui prouve que l'installation est sécurisée. Chaque ligne doit
donner le résultat indiqué.

**VPS**

```sh
cd /srv/n8n

# 1. n8n répond sur la boucle locale.                     Attendu : 200
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:5678/healthz

# 2. Il n'écoute QUE sur la boucle locale.                Attendu : 127.0.0.1:5678
sudo ss -tlnp | grep ':5678 '

# 3. La base n'a aucune route vers Internet.               Attendu : base isolée
sudo docker compose exec -T n8n-db sh -c \
  'wget -q -T 5 -O /dev/null http://1.1.1.1 && echo "base JOIGNABLE : ANOMALIE" || echo "base isolée"'

# 4. n8n ne voit pas le site ni le frontal.                Attendu : introuvable
sudo docker compose exec -T n8n node -e \
  "require('dns').lookup('site-web',e=>console.log(e?'site-web introuvable':'site-web JOIGNABLE : ANOMALIE'))"

# 5. n8n n'a aucune capacité système.                      Attendu : 0000000000000000
sudo docker compose exec -T n8n grep CapEff /proc/1/status

# 6. Le site, lui, n'a pas bougé.                          Attendu : 200
curl -s -o /dev/null -w '%{http_code}\n' https://preventioncambriolage.fr/
```

Puis depuis le poste, le port ne doit pas répondre de l'extérieur :

**PowerShell**

```powershell
Test-NetConnection <vps> -Port 5678
```

Attendu : `TcpTestSucceeded : False`.

---

## Étape 9 — Ouvrir l'éditeur par le tunnel

Pour ne pas retaper la commande, déclarez le tunnel une fois dans le fichier
`C:\Users\<vous>\.ssh\config` du poste (créez-le s'il n'existe pas) :

```
Host n8n
    HostName <vps>
    User <compte>
    IdentityFile <clé>
    IdentitiesOnly yes
    LocalForward 127.0.0.1:5678 127.0.0.1:5678
    ExitOnForwardFailure yes
    ServerAliveInterval 60
```

Puis, chaque fois que vous voulez travailler dans n8n :

**PowerShell**

```powershell
ssh -N n8n
```

La fenêtre reste muette tant que le tunnel est ouvert ; `Ctrl+C` le ferme.
Ouvrez alors <http://localhost:5678> dans le navigateur.

Sans fichier de configuration, la commande équivalente est :

```powershell
ssh -N -i <clé> -L 127.0.0.1:5678:127.0.0.1:5678 <compte>@<vps>
```

Si le poste utilise déjà le port 5678, prenez un autre port local
(`-L 127.0.0.1:15678:127.0.0.1:5678`, puis <http://localhost:15678>). Le port
côté serveur, lui, reste 5678 : c'est le seul que `PermitOpen` autorise.

### Premier accès : créer le compte propriétaire tout de suite

À la première ouverture, n8n demande de créer le compte propriétaire. Faites-le
**immédiatement** : tant qu'il n'existe pas, quiconque atteint l'éditeur peut
le créer à votre place. Seul votre tunnel y mène, mais on ne laisse pas une
installation dans cet état.

1. Adresse e-mail et **mot de passe long généré par le gestionnaire de mots de
   passe**.
2. Dans *Settings → Personal*, activer l'**authentification à deux facteurs**
   et ranger les codes de secours dans le gestionnaire.
3. Ne pas installer de nœud communautaire : c'est de toute façon désactivé
   (`N8N_COMMUNITY_PACKAGES_ENABLED=false`).
4. Pour chaque identifiant enregistré plus tard, demander au service tiers le
   **jeton aux droits les plus réduits** possibles. n8n peut joindre tout
   Internet, c'est sa fonction ; la portée des jetons est la seule limite à ce
   qu'un workflow compromis pourrait faire.

---

## Étape 10 — Sauvegarder

En attendant les sauvegardes chiffrées hors machine de la PR #2, voici la
sauvegarde manuelle. Elle est **obligatoire avant toute mise à jour**.

**VPS**

```sh
cd /srv/n8n
F=/srv/n8n/sauvegardes/n8n-$(date +%F-%H%M).dump
sudo docker compose exec -T n8n-db pg_dump -U n8n -d n8n -Fc | sudo tee "$F" >/dev/null
sudo cp .env "/srv/n8n/sauvegardes/env-$(date +%F-%H%M)"
sudo ls -la /srv/n8n/sauvegardes
```

Une installation vide donne un fichier d'environ 500 ko ; **un fichier de
quelques octets signale un échec**.

Ce que contient la sauvegarde, et ce qui manque :

| Élément | Où | Sauvegardé ici |
|---|---|---|
| Workflows, identifiants (chiffrés), comptes, historique | base PostgreSQL | oui |
| Clé de chiffrement | `secrets/chiffrement.env` | non : elle est dans votre gestionnaire de mots de passe (étape 6) |
| Configuration | `.env`, `docker-compose.yml` | `.env` oui ; le reste se retrouve dans ce guide |
| Fichiers manipulés par les workflows | volume `n8n_n8n_fichiers` | non |

Cette sauvegarde reste **sur le VPS** : elle protège d'une mise à jour ratée,
pas de la perte de la machine. Les vidages contiennent les identifiants
chiffrés et l'historique d'exécution, donc des données personnelles : ils ne
vont pas dans git. Supprimez les anciens à la main (`sudo rm`) pour ne garder
que les trois derniers.

### Restaurer

**VPS**

```sh
cd /srv/n8n
F=/srv/n8n/sauvegardes/n8n-AAAA-MM-JJ-HHMM.dump   # le vidage à restaurer

sudo docker compose stop n8n
sudo docker compose exec -T n8n-db dropdb -U n8n n8n
sudo docker compose exec -T n8n-db createdb -U n8n n8n
sudo sh -c "docker compose exec -T n8n-db pg_restore -U n8n -d n8n --no-owner < $F"
sudo docker compose start n8n
sudo docker compose ps
```

La restauration ne fonctionne qu'avec la **même clé de chiffrement** que celle
qui a produit le vidage.

---

## Étape 11 — Mettre à jour (manuellement, après sauvegarde)

n8n ne se met jamais à jour tout seul : pas d'instance `maj@n8n`, et c'est
voulu.

1. Lire les notes de version entre la version installée et la cible
   (<https://docs.n8n.io/release-notes/>), en particulier toute rubrique
   *Breaking changes*. Ne jamais sauter une version majeure.
2. Sauvegarder (étape 10).
3. Changer la version et relancer :

**VPS**

```sh
cd /srv/n8n
sudo sed -i 's#^N8N_IMAGE=.*#N8N_IMAGE=docker.n8n.io/n8nio/n8n:X.Y.Z#' .env   # X.Y.Z = la cible
sudo docker compose pull n8n
sudo docker compose up -d n8n
sudo docker compose logs -f n8n     # Ctrl+C une fois « Editor is now accessible » affiché
sudo docker compose ps
```

4. Refaire les contrôles 1, 2 et 5 de l'étape 8, ouvrir l'éditeur et lancer un
   workflow à la main.

**Retour arrière :** les migrations de base ne se défont pas. Remettre
l'ancienne version dans `.env` ne suffit pas : il faut aussi restaurer le
vidage pris juste avant (étape 10, « Restaurer »), puis
`sudo docker compose up -d n8n`.

Les images remplacées s'accumulent (1,8 Go chacune) : après quelques jours sans
problème, `sudo docker image prune -f`.

---

## Dépannage

| Symptôme | Cause | Remède |
|---|---|---|
| `unauthorized` sur un `docker pull` | `DOCKER_CONFIG` de votre shell | passer par `sudo docker …` |
| n8n redémarre en boucle, `EACCES … /run/secrets/mdp_postgres` | le mot de passe de la base n'appartient pas à l'uid 1000 | `sudo chown 1000:1000 /srv/n8n/secrets/mdp_postgres` puis `sudo docker compose up -d` |
| n8n redémarre en boucle, `JavaScript heap out of memory` | `NODE_OPTIONS` absent du `.env` | refaire l'ajout de l'étape 4 |
| `n8n's address '::' is not available` | `N8N_LISTEN_ADDRESS` absent du `.env` | refaire l'ajout de l'étape 4 |
| `channel 2: open failed: administratively prohibited` dans la fenêtre du tunnel | la destination du tunnel n'est pas exactement `127.0.0.1:5678` | utiliser `127.0.0.1`, pas `localhost`, après le second `:` |
| `bind … Address already in use` sur le poste | un programme local occupe déjà 5678 | autre port local, voir l'étape 9 |
| Après une restauration, les identifiants enregistrés ne fonctionnent plus | clé de chiffrement différente de celle du vidage | remettre la clé d'origine dans `secrets/chiffrement.env`, puis `sudo docker compose up -d --force-recreate n8n` |

---

## Corrections à reporter dans la PR #2

L'installation de test a révélé trois défauts dans `services/n8n/` de la
PR #2. Ce guide les contourne à l'étape 4 et à l'étape 6 ; ils sont à corriger
à la source :

1. **n8n ne démarre pas** : le mot de passe de la base, en `0600 root:root`,
   est monté tel quel dans le conteneur, où n8n tourne en uid 1000 et ne peut
   pas le lire (`EACCES`). Il doit appartenir à l'uid 1000.
2. **n8n 2.x meurt au démarrage** faute de tas JavaScript avec la limite de
   1536 Mo (`--max-old-space-size` à fixer), et refuse d'écouter si `::`
   n'est pas disponible (`N8N_LISTEN_ADDRESS`).
3. **`NODES_EXCLUDE` réautorise Local File Trigger** sur n8n 2.x, qui
   l'interdit par défaut. Et PostgreSQL 16 est désormais signalé hors plage
   par n8n.

Le volume `n8n_fichiers` créé au nom de root, et les commentaires qui donnent
un tunnel vers `localhost` (refusé dès que `PermitOpen` est en place), sont à
reprendre au même endroit.
