# Sauvegardes

Le principe posé pour ce projet : **puisqu'on part d'une infrastructure décrite
en code, tout ce qui peut vivre dans GitHub y vit, et on ne sauvegarde que le
reste.** La meilleure sauvegarde est celle qu'on n'a pas besoin de faire, parce
que la chose se rejoue depuis un dépôt.

Ce qui suit range donc chaque donnée dans l'un de trois niveaux, et le dernier
seul relève d'un dispositif de sauvegarde classique.

---

## Niveau 1 — déjà dans GitHub, rien à sauvegarder

| Donnée | Où |
|---|---|
| piles Docker Compose, Caddyfile, unités systemd | ce dépôt |
| schéma et migrations de l'annuaire | dépôt de l'application |
| scripts d'import des données ouvertes | dépôt de l'application |
| image du site et des applications | registre `ghcr.io`, reconstruite depuis le code |
| le corps de l'annuaire issu de Sirene et des bases publiques | **se réimporte**, donc ne se sauvegarde pas |

Ce dernier point vaut d'être souligné : une base de plusieurs gigaoctets
recomposable en une commande n'est pas une donnée à sauvegarder, c'est un
cache. Sauvegarder ce qui se régénère coûte du stockage et masque ce qui compte
vraiment.

---

## Niveau 2 — peut aller dans GitHub, et y va

**Les workflows n8n.** C'est la valeur réelle de n8n, et ce sont des données
structurées, versionnables, comparables d'une version à l'autre. Elles n'ont
aucune raison de vivre uniquement dans une base de données sur une machine.

Un export automatique chaque nuit
([`export-workflows-n8n.sh`](../../services/_commun/export-workflows-n8n.sh))
sort les workflows en JSON, un fichier par workflow, et les commite dans un
**dépôt privé dédié**. On y gagne trois choses que la sauvegarde par instantané
ne donne pas : l'historique des modifications, la possibilité de voir ce qui a
changé et quand, et la restauration d'un seul workflow sans toucher au reste.

Trois garde-fous, parce que cette commodité a un prix :

**Les identifiants ne sont jamais exportés.** `n8n export:workflow` ne les
inclut pas. La commande qui les exporterait existe ; elle n'est pas utilisée,
et ne doit pas l'être.

**Un workflow peut contenir un secret en dur** — un jeton écrit dans un nœud
« Code », une URL avec une clé dedans. Le script refuse de commiter s'il
détecte un motif de jeton connu. C'est un filet, pas une garantie : un secret
qui ne ressemble à rien de connu passera.

**Un workflow peut aussi contenir des données personnelles** : une adresse
e-mail écrite en dur comme destinataire, une liste de contacts dans un nœud.
L'historique Git étant immuable, elles y resteraient. Le script signale les
adresses e-mail trouvées dans les fichiers exportés — à l'auteur du workflow de
les sortir vers un identifiant ou une variable, ce qui est de toute façon la
bonne pratique.

**Le dépôt est privé, distinct du dépôt d'infrastructure, et le jeton qui
l'alimente n'a de droit que sur lui.** Écrire depuis le VPS vers GitHub suppose
un jeton d'écriture sur la machine : si elle est compromise, ce jeton l'est
aussi. Qu'il ne puisse rien faire d'autre que pousser les workflows est ce qui
rend l'affaire acceptable — un jeton qui pourrait modifier le dépôt
d'infrastructure permettrait d'altérer ce qu'on rejouera pour reconstruire le
serveur.

---

## Niveau 3 — ne peut pas aller dans GitHub

Trois raisons distinctes, et la deuxième est celle qu'on oublie.

**Les secrets n'y vont pas**, même chiffrés : les déposer chez un tiers, c'est
déplacer le problème d'un cran, pas le résoudre.

**L'historique Git est immuable.** C'est sa qualité principale, et
précisément ce qui le rend impropre aux données personnelles : une demande
d'effacement ne peut pas être honorée sur un historique Git sans le réécrire
entièrement — et il faudrait encore le réécrire chez tous ceux qui l'ont
cloné. Une donnée personnelle commitée par erreur ne se retire pas, elle se
constate. Le droit à l'effacement et Git sont mécaniquement incompatibles.

**La volumétrie**, accessoirement : Git n'est pas fait pour des fichiers
binaires qui changent.

| Donnée | Raison |
|---|---|
| identifiants d'API n8n (chiffrés en base) | secrets |
| clé de chiffrement n8n | secret ; vit dans un gestionnaire de mots de passe, hors serveur |
| historique d'exécution n8n | données personnelles — ce que les workflows manipulent |
| fiches revendiquées, contributions d'artisans | données personnelles |
| liste d'exclusion RGPD | données personnelles, et perdre cette liste republierait ce qu'on a retiré |
| fichiers déposés | volumétrie, et données personnelles |

C'est peu de choses, et c'est irremplaçable. D'où un dispositif qui ne
s'applique qu'à cela.

**`restic` vers un stockage objet OVH, chiffré côté client, une fois par jour.**

```
02h00  pg_dump des deux bases  ─┐
02h05  copie des volumes       ─┼─→  /var/sauvegardes/  ─→  restic  ─→  Object Storage
                                │      (3 jours,             (chiffré        (S3, région
03h00  vérification restic     ─┘       restauration          côté           différente
                                        immédiate)            client)        du VPS)
```

Pourquoi `pg_dump` et pas une copie du volume PostgreSQL : copier les fichiers
d'une base **en cours d'écriture** produit une sauvegarde qui restaure parfois,
et se découvre le jour où elle ne restaure pas. Un `pg_dump` est cohérent par
construction.

Pourquoi `restic` : il déduplique et chiffre **avant** l'envoi. Le prestataire
de stockage n'a jamais les données en clair, ce qui rend le choix du
prestataire beaucoup moins engageant.

Pourquoi une région différente : une sauvegarde dans le même centre de données
que la machine sauvegardée protège d'une bêtise, pas d'un sinistre. Le
précédent OVH de Strasbourg en mars 2021 est la référence en la matière.

---

## Le roulement

Trois échelles, qui se recouvrent volontairement :

| Où | Cadence | Conservé | Sert à |
|---|---|---|---|
| sur le VPS | quotidienne | 3 jours | restaurer tout de suite, sans téléchargement |
| stockage objet | quotidienne | 7 | la bêtise de la semaine |
| stockage objet | hebdomadaire | 4 | la panne découverte en rentrant de congés |
| stockage objet | mensuelle | 6 | la corruption silencieuse, qui se voit tard |

Six mois n'est pas un chiffre décoratif : une suppression malveillante ou une
corruption progressive se découvre souvent des semaines après. Sept jours ne
couvrent que la panne franche.

Et un plafond, dans l'autre sens : **rien au-delà de ce qui est nécessaire.**
Les sauvegardes contiennent des données personnelles, et leur durée de
conservation fait partie du registre des traitements — voir
[`donnees-personnelles.md`](donnees-personnelles.md).

**Le roulement ne s'opère pas depuis le VPS.** C'est délibéré, voir
ci-dessous : `restic forget --prune` se lance à la main depuis le poste de
l'administrateur, une fois par mois.

---

## Le rançongiciel, et pourquoi deux jeux d'identifiants

Une sauvegarde accessible en écriture depuis la machine sauvegardée est
chiffrée en même temps qu'elle par un rançongiciel. C'est le mode opératoire
courant, pas un cas d'école.

| Jeu | Droits | Où |
|---|---|---|
| `sauvegarde` | `PutObject`, `GetObject`, `ListBucket` — **pas de suppression** | sur le VPS |
| `entretien` | droits complets, pour `restic forget --prune` | **jamais sur le VPS**, sur le poste de l'administrateur |

Conséquence assumée : **la purge n'est pas automatique.** Une purge lancée
depuis le serveur exigerait d'y laisser le droit de supprimer, ce qui annule
tout le bénéfice. C'est un rendez-vous mensuel, et c'est le prix du dispositif.

Le versionnement d'objets est activé sur le bucket, ce qui rattrape un
écrasement.

Même logique pour le jeton GitHub du niveau 2 : droit d'écriture sur un seul
dépôt privé, et rien d'autre.

---

## La vérification

Une sauvegarde qu'on n'a jamais restaurée n'est pas une sauvegarde, c'est une
croyance.

| Contrôle | Fréquence | Comment |
|---|---|---|
| intégrité du dépôt | hebdomadaire | `restic check --read-data-subset=5%` |
| **restauration réelle** | mensuelle | [`restauration-test.sh`](../../services/_commun/restauration-test.sh) |
| export des workflows | quotidien | l'échec du commit déclenche l'alerte |
| alerte en cas d'échec | à chaque exécution | `OnFailure=` systemd |

`restauration-test.sh` ne se contente pas de télécharger : il restaure le
dernier `pg_dump` dans un PostgreSQL jetable, puis compte les lignes. Une
sauvegarde qui restaure une base vide passe tous les contrôles de fichiers et
ne vaut rien.

**Sans alerte sur l'échec, ces contrôles ne servent à rien** : personne ne lit
un journal qui va bien.

---

## Restaurer

Le mode d'emploi doit être lisible un dimanche soir, par quelqu'un d'énervé.

**Un workflow n8n perdu** — le cas le plus fréquent, et le plus simple :

```bash
# Depuis le dépôt privé des workflows, sur n'importe quelle machine.
git log --oneline -- workflows/mon-workflow.json
git show <commit>:workflows/mon-workflow.json > /tmp/w.json
# Puis import depuis l'interface n8n, ou :
docker compose -f /opt/vps/services/n8n/docker-compose.yml exec -T n8n \
  n8n import:workflow --input=/dev/stdin < /tmp/w.json
```

**Une base entière :**

```bash
restic snapshots                                   # ce qui est disponible
restic restore <id> --target /var/restauration     # récupérer

docker compose -f /opt/vps/services/n8n/docker-compose.yml stop n8n
docker compose -f /opt/vps/services/n8n/docker-compose.yml exec -T n8n-db \
  pg_restore -U n8n -d n8n --clean --no-owner < /var/restauration/.../n8n.dump
docker compose -f /opt/vps/services/n8n/docker-compose.yml start n8n
```

**Pour n8n, la clé de chiffrement doit être celle d'origine.** Si elle a été
régénérée entre-temps, les workflows reviennent — ils sont dans GitHub de toute
façon — mais tous les identifiants enregistrés sont illisibles et à ressaisir.
C'est la raison pour laquelle elle est conservée hors ligne.

**Le serveur entier :** on rejoue le socle depuis ce dépôt, puis on restaure le
niveau 3. C'est tout l'intérêt de l'infrastructure décrite en code, et c'est
précisément le chemin qui doit être essayé une fois pour de vrai.

---

## Ce que ce dispositif ne couvre pas

- **Le mot de passe `restic`.** Perdu, le dépôt entier est irrécupérable, par
  conception. Il va au même endroit que la clé n8n : un gestionnaire de mots de
  passe, hors du serveur.
- **La reconstruction complète, tant qu'elle n'a pas été essayée.** Rejouer le
  socle sur un VPS jetable puis restaurer, au moins une fois, sinon ce chemin
  reste théorique — et un chemin de reprise théorique n'en est pas un.
- **Une supervision.** Rien ne prévient aujourd'hui si un service tombe. C'est
  un prérequis, pas un confort, dès lors qu'on héberge autre chose que des
  pages statiques, et le seul dispositif qui ne dépende pas de la machine
  surveillée.
