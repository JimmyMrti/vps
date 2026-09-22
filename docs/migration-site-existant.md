# Reprendre le site en production sans le couper

À lire **avant** de jouer le playbook sur la machine de production.

Le site tourne. Il a ses conteneurs, son Caddy, ses certificats. Le socle
décrit une organisation différente, et la bascule de l'une à l'autre est le
seul moment vraiment risqué de tout ce chantier.

---

## Ce qui change exactement

| Aujourd'hui | Après |
|---|---|
| L'emplacement réel de la pile — **à relever, étape 0** | `/opt/vps/site/` et `/opt/vps/frontal/` |
| Le Caddy en place, quel qu'il soit | Le frontal mutualisé, partagé avec n8n et l'annuaire |
| Le volume de certificats de ce Caddy — **à relever** | Volume `frontal_certificats` |
| Fichiers déposés à la main | Fichiers écrits par Ansible |
| Le réseau de la pile en place | Réseau `edge` |
| Conteneur `web` | Conteneur `web` *(inchangé)* |
| `ufw` | `nftables` + chaîne `DOCKER-USER` |

> **La colonne de gauche est une inconnue, pas une donnée.** Elle a d'abord été
> remplie d'après la procédure d'installation du dépôt du site
> (`/opt/preventioncambriolage/`, volume `preventioncambriolage_caddy_data`).
> Jim a depuis signalé que le frontal en place charge
> `/srv/proxy/sites/preventioncambriolage.caddy` : la machine a divergé de sa
> procédure. Les chemins écrits d'avance ont donc été retirés de cette page au
> profit de l'étape 0, qui les relève sur la machine. Une procédure de bascule
> qui se trompe de chemin échoue au pire moment, et son retour arrière avec
> elle.

Ce qui **ne** change **pas** : l'image du site, son contenu, sa configuration
nginx, sa chaîne de construction, et le fait que le serveur va chercher ses
mises à jour.

---

## Les cinq pièges

### 1. Deux Caddy ne peuvent pas tenir le port 443

Tant que l'ancienne pile tourne, le frontal ne démarre pas : le port est pris.
Il faut donc arrêter l'ancienne **avant** de démarrer la nouvelle, et c'est
la fenêtre de coupure. Elle dure le temps que le frontal obtienne son premier
certificat — quelques secondes si tout va bien, quelques minutes sinon.

### 2. Le nouveau frontal repart sans certificat

Les certificats vivent dans le volume de l'ancienne pile. Le nouveau frontal a
son propre volume, vide : il redemandera un certificat pour
`preventioncambriolage.fr`.

**Let's Encrypt limite à cinq certificats identiques par semaine.** Une
bascule qui échoue et qu'on recommence quatre fois épuise le quota, et il n'y
a alors plus rien à faire qu'attendre sept jours — avec un site hors ligne.

C'est la raison d'être de la répétition ci-dessous.

### 3. Le conteneur du site ne s'appelle pas pareil des deux côtés

En production, le conteneur du site s'appelle **`site-web`**. Le dépôt le
nomme **`web`**. Le fichier de site du dépôt écrit donc `reverse_proxy
web:8080`, et ce nom ne résout pas tant que l'ancienne pile est en place : le
frontal démarre, obtient son certificat, et répond 502 à tout le monde.

Ce n'est pas une divergence à corriger d'un côté ou de l'autre. `site-web`
n'est le nom de personne : c'est celui que Compose fabrique à partir du projet
`site` et du service `web`. La pile du dépôt épingle `container_name: web`,
ce qui fixe le nom au lieu de le laisser dépendre du nom du dossier. Les deux
désignent le même service ; seul le nom visible change, et il change **au
moment où la nouvelle pile du site démarre**.

D'où la seule règle qui compte : à l'étape 5, le frontal et le site se
déploient **ensemble**, `--tags proxy,site`. Jouer `--tags proxy` seul met en
place un frontal qui pointe sur un conteneur qui n'existe pas encore.

### 4. Les fichiers de site en place importent un extrait nommé `commun`

Le frontal en place charge ses fichiers depuis `/srv/proxy/sites/` et ils
importent un extrait partagé sous le nom `commun`. Le Caddyfile du socle ne
définit pas ce nom : ses extraits à lui portent d'autres noms, dont
`tls_anssi` pour le profil TLS.

Recopier ces fichiers tels quels dans `edge/sites/` ne passe donc pas. La
bonne nouvelle est que ça ne passe pas **tôt** : le rôle `proxy` fait tourner
`caddy validate` avant de démarrer quoi que ce soit, et un extrait inconnu y
est refusé. L'échec arrive pendant le déploiement, pas devant les visiteurs.
Il reste à faire la correspondance à la main, extrait par extrait, en lisant
ce que `commun` contient réellement — un réglage qui s'y trouve et que le
socle ne reprend pas serait perdu en silence.

### 5. Les unités systemd portent le même nom des deux côtés

La mise à jour automatique du site est aujourd'hui assurée par
`maj-site.timer` et `maj-site.service`. Le rôle `maj_service` du socle nomme
les siennes à partir de `maj_nom`, qui vaut `site` : **exactement les mêmes
noms de fichiers**, dans le même `/etc/systemd/system/`.

C'est une bonne nouvelle pour la bascule et un piège pour le retour arrière.

Bonne nouvelle : aucun minuteur orphelin ne survit. Sans cela, l'ancien
minuteur continuerait de se déclencher toutes les dix minutes après la
bascule et relèverait l'ancienne pile tout seul — une bascule qui se défait
d'elle-même dans le quart d'heure, sans que personne ait rien fait.

Piège : à la seconde où `--tags site` s'exécute, le fichier d'unité de
production est **écrasé** et pointe sur `/opt/vps/site/maj.sh`.
L'ancienne pile, si on y revient, revient sans son minuteur, pendant que le
nouveau continue de démarrer la nouvelle pile toutes les dix minutes. Deux
piles du même site tournent alors en parallèle et personne ne comprend
pourquoi.

D'où deux gestes : **copier les deux fichiers d'unité avant la bascule**
(étape 0), et **arrêter le nouveau minuteur avant de remonter l'ancienne
pile** (retour arrière).

---

## Une note sur `/opt` contre `/srv`

L'arborescence de déploiement de la machine est sous `/srv/` — `/srv/proxy/`,
`/srv/preventioncambriolage/` — là où la documentation du dépôt du site
annonce `/opt/`. Le socle, lui, écrit sous `/opt/vps/`.

Ce n'est pas aligné, et ce n'est pas un oubli. `/srv` n'est la décision de
personne : c'est là que la machine a dérivé, sans que rien ne l'écrive. Adopter
une dérive comme convention parce qu'elle existe, c'est lui donner après coup
une autorité qu'elle n'a jamais eue. Le socle fixe donc une racine unique et
la déclare : `vps_racine`, une seule variable, changeable d'une ligne si vous
préférez `/srv/vps`.

Ce qui compte pour la bascule n'est pas le choix mais sa conséquence :
**l'ancienne arborescence est ailleurs, donc rien n'est écrasé et tout reste
orphelin.** Les deux dossiers `/srv/proxy/` et `/srv/preventioncambriolage/`
survivent à la bascule, et c'est l'étape 7 qui s'en occupe — pas l'un des
deux, les deux.

---

## Procédure

### Étape 0 — Relever ce qui tourne vraiment

**À faire en premier, et à refaire le jour de la bascule.** Cette page ne
connaît pas la machine : elle connaît la procédure d'installation, dont la
machine a déjà divergé au moins une fois. Tout ce qui suit s'appuie sur les
trois variables relevées ici, et sur rien d'écrit d'avance.

> **Ce qui a déjà été relevé, au 22/09/2026 :** le frontal en place est un
> conteneur `caddy:2.8-alpine` nommé `proxy-caddy-1` — donc un projet Compose
> `proxy`, service `caddy` —, il charge ses fichiers de site depuis
> `/srv/proxy/sites/`, et ces fichiers importent un extrait partagé nommé
> `commun`. Le conteneur du site s'appelle `site-web`.
>
> Ces valeurs sont un point de départ pour le relevé, pas un raccourci qui
> permettrait de le sauter. Elles datent, elles viennent d'un rapport et non
> d'un relevé fait par la personne qui bascule, et la machine a déjà montré
> qu'elle bougeait sans que le dépôt le sache. Le volume des certificats, en
> particulier, n'a pas été relevé : un projet nommé `proxy` le ferait attendre
> sous `proxy_caddy_data`, mais un `volumes:` nommé explicitement dans le
> fichier compose change cela.

```bash
# Qui tient les ports 80 et 443 ?
docker ps --format '{{.Names}}\t{{.Image}}\t{{.Ports}}'
FRONTAL_ACTUEL=<le nom relevé ci-dessus>

# D'où sort-il ? project.working_dir donne le dossier de la pile,
# project.config_files le ou les fichiers compose à passer à --file.
docker inspect "$FRONTAL_ACTUEL" \
  --format '{{index .Config.Labels "com.docker.compose.project"}}
{{index .Config.Labels "com.docker.compose.project.working_dir"}}
{{index .Config.Labels "com.docker.compose.project.config_files"}}'
PILE_ACTUELLE=<le working_dir relevé>
COMPOSE_ACTUEL=<le config_files relevé>

# Où sont ses certificats ? Le volume monté sur /data pour Caddy.
docker inspect "$FRONTAL_ACTUEL" \
  --format '{{range .Mounts}}{{.Type}} {{.Name}}{{.Source}} -> {{.Destination}}
{{end}}'
VOLUME_CERTIFICATS=<le nom du volume monté sur /data>
```

Trois pièges dans ce relevé :

- **Le nom du volume n'est pas devinable.** Compose le préfixe du nom du
  projet, lui-même tiré du nom du dossier. Une pile déplacée de
  `/opt/preventioncambriolage/` vers `/srv/proxy/` fait passer
  `preventioncambriolage_caddy_data` à `proxy_caddy_data`. C'est exactement ce
  que le signalement de Jim laisse attendre.
- **Le montage peut être un dossier, pas un volume.** `{{.Type}}` vaut alors
  `bind` et c'est `{{.Source}}` qu'il faut sauvegarder, avec `tar` sur la
  machine plutôt que dans un conteneur.
- **`config_files` peut lister plusieurs fichiers**, séparés par des virgules,
  auquel cas chaque `docker compose` de cette page prend un `-f` par fichier.
  Un `down` qui n'en passe qu'un ne s'adresse pas à la même pile et laisse les
  ports pris.

Relever aussi ce que ce frontal sert déjà, pour ne rien laisser orphelin :

```bash
# Le signalement mentionne /srv/proxy/sites/ : ce dossier a la même forme que
# le contrat edge/sites/ du socle. Son contenu réel décide si la bascule est
# une reprise (on recopie ces fichiers dans edge/sites/) ou un remplacement.
#
# Les chemins se lisent dans le relevé des montages ci-dessus : prendre la
# source, côté hôte, de ce qui est monté sur le dossier de configuration de
# Caddy. Ne pas supposer /etc/caddy à l'intérieur ni /srv/proxy à l'extérieur.
cat  <source montée sur le Caddyfile>
ls -l <source montée sur le dossier des sites>
cat  <source montée sur le dossier des sites>/*.caddy
```

Si ces fichiers décrivent des domaines ou des réglages que `edge/sites/` du
dépôt ne reprend pas, **la bascule les perd**. Ils doivent être portés dans le
dépôt avant l'étape 5, pas après : le socle déploie `edge/sites/` et supprime
du serveur tout fichier de site absent du dépôt.

Enfin, mettre de côté les unités systemd de la mise à jour automatique, que la
bascule va écraser puisqu'elle leur donne les mêmes noms :

```bash
sudo cp -a /etc/systemd/system/maj-site.service /root/maj-site.service.avant
sudo cp -a /etc/systemd/system/maj-site.timer   /root/maj-site.timer.avant
systemctl list-timers --all | grep -i maj   # voir s'il y en a d'autres
sudo systemctl cat maj-site.service | grep -E 'ExecStart|WorkingDirectory'
```

Ce `grep` donne au passage la seconde arborescence à relever : le dossier de la
pile du **site**, distinct de celui du frontal — `/srv/preventioncambriolage/`
d'après le dernier relevé.

```bash
SITE_ACTUEL=<le dossier relevé ci-dessus>
```

### Étape 1 — Éprouver ailleurs

Sur une machine jetable, ou avec `proxy_acme_essai: true`, vérifier que le
frontal démarre et sert le site. Un `acme_ca` de test n'entame pas le quota.

> **HSTS interdit de vérifier un certificat de test dans un navigateur.**
> `preventioncambriolage.fr` envoie `includeSubDomains` et `preload` : le
> navigateur refusera un certificat de test sans proposer de passer outre.
> Vérifiez avec `curl` ou `openssl s_client`, jamais dans un navigateur.

### Étape 2 — Sauvegarder les certificats actuels

Cinq minutes qui peuvent éviter sept jours d'attente.

```bash
docker run --rm \
  -v "$VOLUME_CERTIFICATS":/source:ro \
  -v /root:/cible alpine \
  tar czf /cible/certificats-avant-bascule.tgz -C /source .
```

**Puis vérifier que l'archive contient quelque chose** — cette commande-ci ne
prévient pas :

```bash
tar tzf /root/certificats-avant-bascule.tgz | grep -c .
ls -l /root/certificats-avant-bascule.tgz
```

Un volume qui n'existe pas n'est pas une erreur pour Docker : il le **crée**,
vide. La commande réussit, l'archive fait quelques dizaines d'octets, et on
s'en aperçoit après la bascule, c'est-à-dire trop tard. Une archive de moins
d'un kilo-octet, ou sans chemin contenant `preventioncambriolage`, signifie
que le nom du volume relevé à l'étape 0 est faux.

### Étape 3 — Abaisser le TTL du DNS

Quelques heures avant, passer `ttl = 300` dans `terraform.tfvars` et
appliquer. Si la bascule tourne mal et qu'il faut repointer ailleurs, on n'a
pas à attendre une heure par tentative.

### Étape 4 — Jouer le socle sans toucher au site

```bash
ansible-playbook durcissement.yml --check --diff   # lire d'abord
ansible-playbook durcissement.yml
ansible-playbook site.yml --tags docker
```

À ce stade, le site tourne toujours sur son ancienne pile. Rien n'a bougé pour
les visiteurs.

> Le passage de `ufw` à `nftables` recharge le filtrage. Gardez une seconde
> session SSH ouverte : si quelque chose se passe mal, elle est votre seul
> recours avant la console KVM.

### Étape 5 — La bascule

Les trois commandes se suivent sans pause. C'est la fenêtre de coupure.

```bash
# 1. Libérer les ports 80 et 443. SANS -v : le volume des certificats reste.
cd "$PILE_ACTUELLE"
docker compose -f "$COMPOSE_ACTUEL" down

# 2. Monter le frontal et la nouvelle pile du site
cd ~/vps
ansible-playbook site.yml --tags proxy,site

# 3. Vérifier immédiatement
curl -sI https://preventioncambriolage.fr/ | head -1     # attendu : HTTP/2 200
curl -sI http://preventioncambriolage.fr/  | head -1     # attendu : 308
```

Si le certificat tarde :

```bash
docker logs -f frontal
```

`certificate obtained successfully` confirme l'émission.

### Étape 6 — Vérifier avant de nettoyer

```bash
ansible-playbook verification.yml
curl -s https://preventioncambriolage.fr/robots.txt
curl -sI https://preventioncambriolage.fr/ | grep -i strict-transport
```

Une page connue, une page inexistante — le site n'a aucune redirection par
choix, une URL absente doit donner une vraie 404 :

```bash
curl -s -o /dev/null -w '%{http_code}\n' https://preventioncambriolage.fr/nexiste-pas
```

Vérifier aussi que c'est bien **le nouveau** frontal qui répond, et pas
l'ancien resté debout : sur le port 443, les deux se ressemblent depuis
l'extérieur.

```bash
docker ps --filter 'publish=443' --format '{{.Names}}'   # attendu : frontal, et lui seul
```

### Étape 7 — Nettoyer, plus tard

**Pas le même jour.** Laissez l'ancienne pile en place, arrêtée, quelques
jours : c'est le retour arrière le plus rapide qui existe.

```bash
# Une fois la confiance établie, et pas avant :
docker volume rm "$VOLUME_CERTIFICATS"
sudo rm -rf "$PILE_ACTUELLE" "$SITE_ACTUEL"
sudo rm -f /root/maj-site.service.avant /root/maj-site.timer.avant
```

Les **deux** dossiers, pas un seul : le frontal et le site ont chacun le leur.
Oublier le second laisse une pile complète, arrêtée, que la prochaine personne
prendra pour la pile en service.

> `rm -rf` sur un chemin relevé par une commande mérite un regard avant la
> touche entrée. `/srv/proxy` n'est pas `/opt/preventioncambriolage` : si
> d'autres choses ont été déposées à côté de la pile du site pendant que la
> machine dérivait de sa procédure, elles partent avec. Listez le dossier
> avant de l'effacer.

Remettre `ttl = 3600`.

---

## Retour arrière

Tant que l'étape 7 n'est pas faite :

```bash
# 1. Couper le minuteur de la NOUVELLE pile. Sans cela, il redémarre celle-ci
#    toutes les dix minutes, en parallèle de l'ancienne qu'on remonte.
sudo systemctl disable --now maj-site.timer

# 2. Arrêter le nouveau frontal et la nouvelle pile du site
docker compose -f /opt/vps/frontal/compose.yml down
docker compose -f /opt/vps/site/compose.yml down

# 3. Rendre à l'ancienne pile son minuteur, que la bascule a écrasé
sudo cp -a /root/maj-site.service.avant /etc/systemd/system/maj-site.service
sudo cp -a /root/maj-site.timer.avant   /etc/systemd/system/maj-site.timer
sudo systemctl daemon-reload
sudo systemctl enable --now maj-site.timer

# 4. Remonter l'ancienne pile
cd "$PILE_ACTUELLE"
docker compose -f "$COMPOSE_ACTUEL" up -d
```

Le site repart sur ses anciens certificats, qui sont toujours valides.

> Ces deux variables viennent de l'étape 0. Un retour arrière se joue sous
> pression, souvent depuis une autre session que celle de la bascule, où elles
> ne sont plus définies. **Écrivez-les quelque part avant de commencer**, en
> clair, sur la même page que le reste de vos notes de bascule.
