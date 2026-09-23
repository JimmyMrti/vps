# n8n

n8n est un ordonnanceur qui **exécute du code écrit dans son interface** et
**détient les identifiants d'API de tous les services qu'il pilote**. C'est,
de loin, le service le plus dangereux des trois : prendre la main sur n8n, ce
n'est pas défigurer un site, c'est repartir avec les clés.

Tout ce qui suit découle de ce constat.

---

## Faut-il seulement exposer n8n ?

La question vient avant celle du nom de domaine, et la réponse par défaut est
**non**.

n8n détiendra les jetons d'accès de tout ce qu'il pilote. Exposer publiquement
le service qui détient toutes les clés demande une justification, pas une
habitude. Or l'exposition ne sert qu'à **une** chose : recevoir des appels
entrants — webhooks et formulaires. Tout le reste de n8n fonctionne sans être
joignable depuis Internet : les déclencheurs programmés, les relevés
périodiques, les appels sortants vers des API.

**Décision : n8n démarre sans aucune exposition publique.** Pas de domaine, pas
de certificat, pas d'entrée dans les journaux de transparence, aucune surface.
L'accès se fait par tunnel SSH :

```bash
ssh -L 5678:localhost:5678 ubuntu@VPS
# puis http://localhost:5678 dans le navigateur
```

Pour que ce tunnel aboutisse, n8n publie son port **sur la boucle locale
uniquement** : `127.0.0.1:5678:5678`. Ce n'est pas la même chose que publier un
port — Docker n'installe la règle de redirection que pour `127.0.0.1`, donc
rien n'est joignable depuis l'extérieur et le contournement d'UFW ne s'applique
pas.

Deux réglages du socle tiennent ce chemin d'accès, et ils vont ensemble :

- **`net.ipv4.conf.all.route_localnet` à 0**, sa valeur par défaut, figée
  explicitement. À 1, un port publié sur la boucle locale redevient joignable
  depuis le réseau.
- **le relais Docker en espace utilisateur laissé actif.** Le désactiver est le
  réflexe habituel — il consomme de la mémoire et masque l'IP source — mais il
  casse les publications sur la boucle locale, qui dépendraient alors de
  `route_localnet`. Relais actif **et** `route_localnet` à 0, c'est exactement
  la combinaison qui donne un port joignable depuis la machine seule.

Et le socle limite le tunnel lui-même : `AllowTcpForwarding local` autorise un
`-L` et refuse un `-R`, qui est la direction dangereuse, et `PermitOpen` ne
laisse atteindre que `127.0.0.1:5678`. Les bases de données ne sont donc pas
joignables par ce moyen.

`edge/sites/n8n.caddy` est donc inactif tant que `N8N_DOMAIN` n'est pas
renseigné : le nom par défaut est en `.localhost`, Caddy fabrique un certificat
interne et ne demande rien à Let's Encrypt.

**Le jour où un workflow a besoin d'un appel entrant**, on renseigne deux
variables et seuls les chemins de webhook deviennent joignables — l'éditeur
n'obtient toujours aucune adresse publique. La mécanique est détaillée à la
section suivante.

Ce que coûte ce choix, honnêtement : certaines intégrations n'ont d'autre
option que le webhook, et d'autres deviennent des relevés périodiques — plus
lents, et consommateurs de quota d'API. C'est un coût réel, mais il se paie au
cas par cas, quand un besoin précis se présente, au lieu d'ouvrir d'emblée une
porte dont personne ne se sert.

---

## Dissocier les webhooks de l'éditeur

C'est la question centrale dès qu'on expose n8n, et elle a une réponse nette.

Un n8n, ce sont deux choses derrière la même application :

- les **appels entrants** — webhooks et formulaires — qui doivent être
  joignables depuis n'importe où, puisque c'est leur objet : un service tiers
  appelle une URL et n8n réagit ;
- l'**éditeur**, sa page de connexion et son API REST, qui n'ont aucune raison
  d'être joignables depuis n'importe où.

**La séparation se fait au frontal, pas dans n8n.** Elle est donc effective
avant que quoi que ce soit n'atteigne l'application, et une faille
d'authentification dans n8n ne suffit pas à entrer.

### La mécanique, concrètement

Un seul domaine public, qui ne répond **qu'aux** chemins d'appel entrant :

| Chemin | Sur le domaine public |
|---|---|
| `/webhook/*`, `/webhook-test/*`, `/webhook-waiting/*` | servis |
| `/form/*`, `/form-waiting/*` | servis |
| `/` — la page de connexion | **404** |
| `/rest/*`, `/api/*` — l'éditeur et l'API | **404** |

404 et non 403 : inutile de confirmer à un inconnu qu'il y a quelque chose
derrière cette adresse. Et aucune redirection vers une page de connexion, qui
reviendrait à annoncer ce qu'on vient de cacher.

L'éditeur, lui, **n'a aucune adresse publique** — ni sur ce domaine, ni sur un
autre. Il n'y a donc pas de formulaire de connexion joignable depuis Internet,
et c'est la différence entre « protégé par un mot de passe » et « absent ».
L'accès passe par le tunnel SSH.

Côté n8n, deux réglages portent cette dissociation, et ils sont indépendants :

```ini
N8N_URL_WEBHOOK=https://<domaine-public>   # les adresses données aux tiers
N8N_URL_EDITEUR=http://localhost:5678      # les liens internes de l'éditeur
```

n8n fabrique l'adresse d'un webhook à partir du premier. Un service tiers
enregistre donc `https://<domaine-public>/webhook/xxxx`, et n'a jamais
connaissance de l'autre.

### Ce que cela ne protège pas

**Un webhook n'est pas authentifié par n8n.** Son URL est un secret d'URL,
rien de plus : elle fuit dans les journaux, les historiques, les
copier-coller. Chaque workflow déclenché par webhook doit vérifier lui-même
l'appelant — signature HMAC quand le service tiers en propose une (GitHub,
Stripe, Brevo…), en-tête d'authentification à défaut. **Un workflow qui agit
sans vérifier est une porte ouverte avec une adresse difficile à deviner.**

C'est le vrai point d'attention de tout le dispositif : la séparation ci-dessus
met l'éditeur hors de portée, mais les webhooks restent des points d'entrée
publics, par construction.

### Et aujourd'hui

**Rien de tout cela n'est en service.** Tant qu'aucun workflow n'a besoin d'un
appel entrant, `N8N_DOMAIN` n'est pas renseignée, le frontal retombe sur
`n8n.localhost`, il ne sert donc aucun domaine public pour n8n, et il
n'existe aucune surface publique du tout — pas même les webhooks. Le fichier
est écrit et prêt ; il suffira de renseigner deux variables le jour venu.

> « Pas renseignée » veut dire **absente de l'environnement, pas assignée à
> vide.** Caddy n'applique le défaut que si la variable n'existe pas ; écrite
> vide, elle produit un bloc de site sans adresse et fait refuser toute la
> configuration du frontal. Voir `edge/sites/README.md`.

---

---

## Le domaine

Le domaine ne sert qu'aux webhooks, et seulement une fois l'exposition
activée. Quand ce jour vient : **un domaine distinct, dédié à
l'infrastructure, et un nom aléatoire dessous.** Aucun sous-domaine de
`preventioncambriolage.fr` : les sites restent séparés.

Le nom du VPS a été envisagé — `vpsXXXXXX.vps.ovh.net`, que OVH crée d'office
et qui pointe déjà sur la machine. **Il ne convient pas**, pour une raison
vérifiable et une autre de fond.

**La raison vérifiable.** Let's Encrypt compte ses quotas par « domaine
enregistré », déterminé à l'aide de la *Public Suffix List*. Or cette liste ne
contient que `*.hosting.ovh.net` et `*.webpaas.ovh.net` — ni `vps.ovh.net`, ni
`ovh.net` (vérifié sur la liste publiée). Le domaine enregistré de
`vpsXXXXXX.vps.ovh.net` est donc `ovh.net`, et **tous les VPS OVH du monde
partagent alors le même quota** de 50 certificats par semaine. Il est
durablement épuisé. La demande de certificat échouerait sur
« too many certificates already issued ».

**La raison de fond.** Ce nom appartient à l'inventaire du fournisseur : il
change si la machine est remplacée, et il annonce l'hébergeur. Une adresse de
service ne doit pas dépendre du matériel qui la sert.

### Ce qui est retenu

Un domaine bon marché dédié à l'infrastructure — en `.ovh` ou en `.fr`, le DNS
étant déjà géré chez OVH — et n8n sur une étiquette aléatoire :

```
k7m2x9qp.<domaine-infra>.tld
```

L'étiquette se tire une fois : `openssl rand -hex 4`.

### Ce qu'un nom aléatoire protège, et ce qu'il ne protège pas

Il protège du **devinage** : personne ne trouvera `k7m2x9qp` dans une liste de
sous-domaines courants.

Il ne protège pas de la **découverte**. Tout certificat Let's Encrypt est
publié dans les journaux de transparence, consultables par n'importe qui sur
`crt.sh`, quelques minutes après l'émission. Un nom aléatoire y apparaît en
clair comme un autre.

**Un certificat générique le cacherait.** Un certificat `*.<domaine-infra>.tld`
obtenu par validation DNS-01 ne publie que l'étoile : l'étiquette aléatoire
n'apparaît nulle part.

**Cette piste a été examinée puis écartée**, et c'est le bon arbitrage. Elle
demande une image Caddy construite avec `xcaddy` — acceptable, elle serait
construite en intégration continue comme l'image du site — mais surtout **une
clé d'API OVH en écriture sur la zone DNS, posée sur le serveur**. Aujourd'hui,
qui prend le serveur prend le serveur ; avec cette clé, il prend aussi les
domaines, donc la possibilité de se faire émettre des certificats valides pour
n'importe quel service. On échangerait une information publique contre un
pouvoir supplémentaire donné à l'attaquant.

Et sur le fond : si la sécurité de n8n reposait sur l'ignorance de son adresse,
elle ne reposerait sur rien. Ce qui la porte, c'est l'absence d'exposition,
puis l'authentification et la restriction d'accès. La décision et les
situations qui la rouvriraient sont écrites dans `docs/adr/0003-acme-http-01.md`,
côté socle.

**La validation HTTP-01 est donc retenue** : le jour où un nom sera nécessaire,
il sera visible dans les journaux de certificats, et c'est assumé.

Ce qui ne marche pas, en revanche : compter sur la discrétion du nom. Elle
n'est pas une mesure de sécurité ; la restriction d'accès en est une.

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
| Cookie de session | `N8N_SECURE_COOKIE` suit le chemin d'accès — voir `.env.example` |
| Nombre de sauts de proxy | `N8N_PROXY_HOPS=1` dès qu'un webhook passe par le frontal |

Le cookie de session n'est marqué « secure » que s'il peut traverser le réseau.
Tant que l'éditeur n'est joint que par tunnel SSH, sur `http://localhost`, il ne
le traverse jamais : le marquer bloquerait simplement la connexion, sans rien
protéger. Il redevient obligatoire le jour où l'éditeur serait servi par le
frontal.

`N8N_PROXY_HOPS` n'est pas un détail non plus : sans lui, la limitation de débit
interne de n8n et ses journaux attribuent tous les appels de webhook à la même
adresse, celle du frontal.

L'authentification des webhooks eux-mêmes est traitée plus haut, à la section
qui les sépare de l'éditeur : elle ne relève pas de n8n mais de chaque
workflow.

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
