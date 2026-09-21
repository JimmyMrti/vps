# Sauvegardes

Jusqu'ici, le VPS n'avait rien à sauvegarder : le site est statique et se
reconstruit depuis GitHub. **n8n et l'annuaire changent complètement la
donne.** Ce qui vit désormais sur la machine et nulle part ailleurs :

| Donnée | Où | Perdre, c'est |
|---|---|---|
| workflows et identifiants n8n | base `n8n-db` | tout réécrire, et ressaisir chaque identifiant d'API |
| clé de chiffrement n8n | `/opt/vps/secrets/n8n/encryption_key` | rendre les sauvegardes n8n **inexploitables** |
| données de l'annuaire | base `annuaire-db` | reprendre l'import, et perdre les contributions |
| fichiers déposés | volume `annuaire_fichiers` | perdre les photos et documents |
| certificats | volume `caddy_data` | peu grave, Caddy en redemande — attention au quota |

Le reste (images, configuration) est dans ce dépôt et dans le registre.

---

## Le dispositif

**`restic` vers un stockage objet OVH, chiffré, une fois par jour.**

```
02h00  pg_dump des deux bases  ─┐
02h05  copie des volumes       ─┼─→  /var/sauvegardes/  ─→  restic  ─→  Object Storage
                                │      (3 jours,             (chiffré        (S3, région
                                │       restauration          côté           différente
                                │       immédiate)            client)        du VPS)
03h00  vérification restic     ─┘
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

## Rétention

| Cadence | Conservé |
|---|---|
| quotidienne | 7 |
| hebdomadaire | 4 |
| mensuelle | 6 |

Six mois, ce n'est pas pour faire joli : une corruption de données ou une
suppression malveillante se découvre souvent des semaines plus tard. Sept jours
de sauvegardes ne couvrent que la panne matérielle.

Et un plafond : **rien au-delà de ce qui est nécessaire**. Les sauvegardes
contiennent des données personnelles ; leur durée de conservation fait partie
du registre des traitements, voir
[`donnees-personnelles.md`](donnees-personnelles.md).

---

## Le rançongiciel, et pourquoi deux jeux d'identifiants

Une sauvegarde accessible en écriture depuis la machine sauvegardée est
chiffrée en même temps qu'elle par un rançongiciel. C'est le mode opératoire
courant, pas un cas d'école.

Deux jeux d'identifiants S3 :

| Jeu | Droits | Où |
|---|---|---|
| `sauvegarde` | `PutObject`, `GetObject`, `ListBucket` — **pas de suppression** | sur le VPS |
| `entretien` | droits complets, pour `restic forget --prune` | **jamais sur le VPS**, sur le poste de l'administrateur |

Conséquence assumée : **la purge n'est pas automatique.** Elle se lance à la
main depuis le poste, une fois par mois. Une purge automatique depuis le
serveur exigerait d'y laisser le droit de supprimer, ce qui annule tout le
bénéfice.

Le versionnement d'objets est activé sur le bucket, ce qui rattrape un écrasement.

---

## La vérification

Une sauvegarde qu'on n'a jamais restaurée n'est pas une sauvegarde, c'est une
croyance.

| Contrôle | Fréquence | Comment |
|---|---|---|
| intégrité du dépôt | quotidienne | `restic check` sur un échantillon de données |
| **restauration réelle** | mensuelle | [`restauration-test.sh`](../../services/_commun/restauration-test.sh) |
| alerte en cas d'échec | à chaque exécution | `OnFailure=` systemd |

`restauration-test.sh` ne se contente pas de télécharger : il restaure le
dernier `pg_dump` dans un PostgreSQL jetable, puis compte les lignes des tables
principales et compare à un seuil. Une sauvegarde qui restaure une base vide
passe tous les contrôles de fichiers et ne vaut rien.

Le résultat est écrit dans le journal systemd. **Sans alerte sur l'échec, ce
contrôle ne sert à rien** : personne ne lit un journal qui va bien.

---

## Restaurer

Le mode d'emploi doit être lisible un dimanche soir, par quelqu'un d'énervé.

```bash
# 1. Ce qui est disponible
restic snapshots

# 2. Récupérer un instantané
restic restore <id> --target /var/restauration

# 3. Arrêter le service concerné
docker compose -f /opt/vps/services/n8n/docker-compose.yml stop n8n

# 4. Réinjecter la base
docker compose -f /opt/vps/services/n8n/docker-compose.yml exec -T n8n-db \
  psql -U n8n -d n8n < /var/restauration/.../n8n.sql

# 5. Redémarrer
docker compose -f /opt/vps/services/n8n/docker-compose.yml start n8n
```

**Pour n8n, la clé de chiffrement doit être celle d'origine.** Si elle a été
régénérée entre-temps, les workflows reviennent mais tous les identifiants
enregistrés sont illisibles. C'est la raison pour laquelle elle est conservée
hors ligne, dans un gestionnaire de mots de passe, et pas seulement sur le
serveur.

---

## Ce que ce dispositif ne couvre pas

- **Le mot de passe `restic`.** Perdu, le dépôt entier est irrécupérable, par
  conception. Il va au même endroit que la clé n8n.
- **La reconstruction du serveur.** Les sauvegardes contiennent les données, pas
  la machine. C'est le rôle du socle infra as code : le jour où le VPS est
  perdu, on rejoue le socle puis on restaure les données. **Ce chemin complet
  doit être essayé au moins une fois**, sur un VPS jetable, sinon il reste
  théorique.
- **Une supervision.** Rien ne prévient aujourd'hui si un service tombe. Un
  service externe de surveillance comble ce manque ; c'est un prérequis, pas un
  confort, dès lors qu'on héberge autre chose que des pages statiques.
