# n8n

n8n est un ordonnanceur qui **exécute du code écrit dans son interface** et
**détient les identifiants d'API de tous les services qu'il pilote**. C'est,
de loin, le service le plus dangereux des trois : prendre la main sur n8n, ce
n'est pas défigurer un site, c'est repartir avec les clés.

Tout ce qui suit découle de ce constat.

---

## Exposition : deux portes, pas une

Un n8n exposé, c'est en réalité deux applications derrière la même adresse :

- les **webhooks**, qui doivent être joignables depuis n'importe où puisque
  c'est tout leur objet — un service tiers appelle une URL et n8n réagit ;
- l'**interface d'administration et l'API REST**, qui n'ont aucune raison
  d'être joignables depuis n'importe où.

Le frontal sépare les deux ([`edge/sites/n8n.caddy`](../../edge/sites/n8n.caddy)) :

| Chemin | Accès |
|---|---|
| `/webhook/*`, `/webhook-test/*`, `/webhook-waiting/*` | public |
| `/form/*`, `/form-waiting/*` | public |
| `/healthz` | public, réservé à la supervision |
| tout le reste : interface, `/rest/*`, `/api/*` | restreint par liste d'adresses IP |

La liste d'adresses n'est pas l'authentification : c'est ce qui fait qu'une
faille d'authentification dans n8n ne se transforme pas en compromission le
jour où elle est publiée. Elle se règle dans `N8N_IP_ADMIN` (voir
`services/n8n/.env.example`).

**Si l'adresse IP du poste n'est pas fixe** — cas courant en connexion
résidentielle — deux options, dans cet ordre de préférence :

1. autoriser le préfixe du fournisseur d'accès, plus large mais toujours mille
   fois plus étroit qu'Internet ;
2. autoriser uniquement le réseau du VPS et passer par un tunnel SSH :
   `ssh -L 5678:n8n:5678 ubuntu@VPS` puis `http://localhost:5678`. Le port
   n'est alors jamais exposé. C'est la solution la plus propre, au prix d'une
   commande à taper.

Le choix par défaut retenu ici est le tunnel SSH, avec la liste d'adresses
laissée vide et donc l'interface fermée. Il suffit d'y écrire une IP pour
ouvrir.

---

## Le domaine

**Recommandation : un domaine distinct, acheté pour l'usage technique.**
Repli utilisable dès aujourd'hui, sans rien acheter :
`auto.preventioncambriolage.fr`.

Trois raisons, dont deux ne sautent pas aux yeux.

**Un sous-domaine annonce publiquement ce qui tourne derrière la marque.** Tout
certificat Let's Encrypt est publié dans les journaux de transparence,
consultables par n'importe qui sur `crt.sh`. Chercher les sous-domaines
commençant par `n8n.` y est un geste d'énumération courant : c'est la liste
toute faite des cibles d'une faille n8n publiée le matin même. Un nom neutre
comme `auto.` retire de cette liste, mais ne masque pas l'association entre le
site éditorial et son outillage.

**L'anonymat de l'éditeur est un choix assumé dans les mentions légales du
site.** Chaque sous-domaine ajouté est une information publique de plus sur son
infrastructure. Un domaine séparé casse le lien.

**HSTS avec `includeSubDomains` est déjà servi** par le site en production.
Conséquence concrète : tout sous-domaine de `preventioncambriolage.fr` doit
être en HTTPS valide **dès la première requête d'un navigateur qui a visité le
site**, essais compris. Ce n'est pas bloquant — Caddy obtient le certificat
seul — mais cela interdit le bricolage en HTTP le temps de mettre au point, et
une erreur de certificat sur un sous-domaine devient un mur, pas un
avertissement qu'on clique.

La variable `N8N_DOMAIN` est le seul endroit à changer pour basculer de l'un à
l'autre. Le repli est là pour ne rien bloquer, pas pour rester.

Ce qui ne marche pas, en revanche : croire qu'un sous-domaine non publié reste
secret. La discrétion n'est pas une mesure de sécurité ; la restriction d'accès
en est une, et c'est elle qui fait le travail ici.

Enregistrement DNS à créer chez OVH avant le premier démarrage de Caddy : un
`A` vers l'IPv4 du VPS, et un `AAAA` vers l'IPv6 s'il y en a une. Un DNS qui ne
résout pas encore fait échouer la demande de certificat.

---

## Authentification

| Mesure | Réglage |
|---|---|
| Compte propriétaire obligatoire | natif depuis n8n 1.x, aucun mode anonyme |
| Double authentification (TOTP) | à activer dans le profil dès la première connexion |
| API publique | désactivée — `N8N_PUBLIC_API_DISABLED=true` |
| Cookie de session | `N8N_SECURE_COOKIE=true`, donc HTTPS obligatoire |
| Nombre de sauts de proxy | `N8N_PROXY_HOPS=1`, sinon n8n voit l'IP de Caddy partout |

`N8N_PROXY_HOPS` n'est pas un détail : sans lui, la limitation de débit interne
de n8n et ses journaux attribuent toutes les requêtes à la même adresse, celle
du frontal.

**Les webhooks ne sont pas authentifiés par n8n.** Une URL de webhook est un
secret d'URL, rien de plus : elle fuit dans les journaux, dans les historiques,
dans les copier-coller. Chaque workflow déclenché par webhook doit vérifier
lui-même l'appelant — signature HMAC quand le service tiers en propose une
(GitHub, Stripe, Brevo…), en-tête d'authentification à défaut. Un workflow qui
agit sans vérifier est une porte ouverte avec une adresse difficile à deviner.

---

## Ce qu'on interdit à n8n

Les réglages ci-dessous ne rendent pas n8n inoffensif ; ils réduisent ce qu'un
workflow malveillant ou maladroit peut atteindre.

| Réglage | Effet |
|---|---|
| `NODES_EXCLUDE=["n8n-nodes-base.executeCommand"]` | plus de commande shell exécutée dans le conteneur |
| `N8N_BLOCK_ENV_ACCESS_IN_NODE=true` | le code d'un nœud ne peut plus lire `process.env`, donc plus la clé de chiffrement ni le mot de passe de la base |
| `N8N_COMMUNITY_PACKAGES_ENABLED=false` | aucune installation de nœud tiers depuis l'interface : une dépendance non auditée s'exécuterait avec tous les droits de n8n |
| `N8N_RESTRICT_FILE_ACCESS_TO=/data/fichiers` | les nœuds fichier ne voient qu'un dossier dédié |
| `N8N_BLOCK_FILE_ACCESS_TO_N8N_FILES=true` | et surtout pas `/home/node/.n8n`, où vit la clé de chiffrement |
| `cap_drop: ALL` + `no-new-privileges` | pas d'escalade dans le conteneur |
| réseau `n8n_interne` en `internal: true` pour la base | la base n8n n'a aucune route vers Internet |

Ce qu'on **ne peut pas** empêcher : n8n appelle des adresses arbitraires sur
Internet, c'est sa fonction. Un workflow compromis peut donc exfiltrer ce qu'il
lit. La seule limite réelle est ce à quoi les identifiants stockés donnent
accès : **ne confier à n8n que des jetons de portée minimale**, jamais un jeton
d'administration là où un jeton en lecture suffit.

---

## La clé de chiffrement

`N8N_ENCRYPTION_KEY` chiffre tous les identifiants stockés en base. Deux
conséquences :

- **Sans elle, une sauvegarde de la base n8n est inexploitable.** Elle doit être
  conservée hors du serveur, dans un gestionnaire de mots de passe.
- **Si elle change, tous les identifiants enregistrés deviennent illisibles** et
  sont à ressaisir un par un.

Elle est générée une fois (`openssl rand -hex 32`) et écrite dans
`/opt/vps/secrets/n8n/encryption_key`, en 0600 root:root. Elle n'apparaît ni
dans le dépôt, ni dans `docker-compose.yml`, ni dans l'historique des commandes.

---

## Historique d'exécutions

Les exécutions conservent **les données qui ont transité** : contenus de
webhooks, réponses d'API, adresses e-mail. C'est à la fois un outil de
diagnostic indispensable et un entrepôt de données personnelles qui grossit
tout seul.

Réglage retenu :

```ini
EXECUTIONS_DATA_PRUNE=true
EXECUTIONS_DATA_MAX_AGE=168          # 7 jours
EXECUTIONS_DATA_PRUNE_MAX_COUNT=5000
EXECUTIONS_DATA_SAVE_ON_SUCCESS=all  # à passer à `none` sur les workflows traitant des données personnelles
```

Sept jours suffisent pour diagnostiquer un incident. Au-delà, on garde des
données de tiers sans raison — voir
[`donnees-personnelles.md`](donnees-personnelles.md).

---

## Ce que la configuration ne couvre pas

- **La limitation de débit sur les webhooks.** Caddy ne sait pas le faire sans
  greffon, et reconstruire Caddy pour cela ajoute une chaîne de compilation à
  maintenir. La parade retenue est un bannissement `fail2ban` alimenté par le
  journal d'accès JSON du frontal
  ([`services/_commun/fail2ban/`](../../services/_commun/fail2ban/)), à
  installer côté socle. Ce n'est pas équivalent : cela punit après coup au lieu
  de lisser.
- **Le filtrage des sorties.** n8n peut joindre n'importe quelle adresse. Une
  liste blanche de destinations est possible via un proxy sortant obligatoire,
  mais elle casse l'usage courant de l'outil. Non retenu à ce stade, à
  reconsidérer si n8n finit par détenir des jetons sensibles.
- **Le mode file d'attente** (`queue mode` avec Redis et des workers séparés).
  Inutile en dessous de plusieurs milliers d'exécutions par jour, et il double
  la consommation mémoire. Voir [`dimensionnement.md`](dimensionnement.md).
