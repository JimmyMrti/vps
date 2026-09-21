# Secrets

Où ils vivent, comment on les change, et ce qui se passe si on en perd un.

---

## Le principe

**Aucun secret en clair dans le dépôt.** Ce qui est versionné est chiffré par
`ansible-vault` ; ce qui ne peut pas l'être vit hors du dépôt.

Un dépôt privé n'est pas un coffre. Un secret poussé une fois reste dans
l'historique Git, où il est lisible par quiconque obtient le dépôt un jour, et
l'en retirer demande de réécrire l'historique — donc de casser toutes les
copies existantes. Le réflexe « c'est privé, ça va » est exactement celui qui
coûte cher.

---

## Le coffre

```bash
cd ansible/inventaire/group_vars/all
cp coffre.yml.example coffre.yml
$EDITOR coffre.yml
ansible-vault encrypt coffre.yml
```

Vérifiez avant de pousser — le fichier doit commencer par l'en-tête du coffre :

```bash
head -1 coffre.yml      # $ANSIBLE_VAULT;1.1;AES256
```

Pour modifier ensuite :

```bash
ansible-vault edit coffre.yml
```

### Le mot de passe du coffre

Il n'est **pas** dans le dépôt. `ansible.cfg` pointe vers
`scripts/coffre-mot-de-passe.sh`, qui le lit dans votre gestionnaire de mots
de passe ou dans une variable d'environnement. Adaptez ce script à votre
outil ; il est prévu pour cela.

---

## Ce qui est dans le coffre

| Secret | Ce qu'il ouvre | Si on le perd |
|---|---|---|
| `coffre_ghcr_jeton` | Lecture du registre d'images | Se régénère sur GitHub. Sans conséquence. |
| `coffre_n8n_cle_chiffrement` | Les identifiants stockés par n8n | **Irréversible.** Voir ci-dessous. |
| `coffre_n8n_postgres_mot_de_passe` | La base n8n | Se change, en le changeant des deux côtés. |
| `coffre_sauvegarde_phrase` | Le dépôt de sauvegarde | **Irréversible.** Voir ci-dessous. |
| `coffre_sauvegarde_s3_*` | Le stockage objet | Se régénère chez OVH. |

## Les deux secrets qu'on ne peut pas régénérer

Ils méritent un traitement à part, parce que les perdre ne se rattrape pas.

**`coffre_n8n_cle_chiffrement`** chiffre les identifiants que n8n conserve
pour ses connecteurs. Sans elle, ces identifiants sont illisibles — y compris
dans les sauvegardes. Restaurer une base n8n avec une autre clé donne une
instance qui démarre et dont aucun connecteur ne fonctionne.

**`coffre_sauvegarde_phrase`** chiffre le dépôt de sauvegarde. Sans elle,
les sauvegardes sont du bruit.

Ces deux-là doivent être **dans un gestionnaire de mots de passe, hors de
cette machine et hors de ce dépôt**. C'est le genre de précaution dont on
mesure l'utilité une seule fois.

---

## Le jeton du registre

GitHub → *Settings → Developer settings → Personal access tokens → Tokens
(classic)*. **Une seule case : `read:packages`.** Rien d'autre.

Un jeton en lecture seule ne permet ni de modifier le code, ni de publier une
image. S'il fuit, l'attaquant peut lire des images privées — ce qui est
désagréable, pas catastrophique.

Il est déposé dans `/etc/docker/identifiants/config.json`, en `0600`, dans un
dossier en `0700`. Pas dans un dossier personnel : le service de mise à jour
tourne en root et son durcissement systemd masque `/home` **et** `/root`.

---

## Changer un secret

```bash
ansible-vault edit ansible/inventaire/group_vars/all/coffre.yml
ansible-playbook site.yml --tags docker        # jeton de registre
```

Pour la base n8n, le mot de passe doit être changé **dans la base aussi** :
PostgreSQL ne le relit pas depuis la variable d'environnement après la
création du volume. La procédure est dans `docs/services/`.

---

## Ce qui ne doit jamais aller sur GitHub

Le principe retenu pour les sauvegardes est que **ce qui se reconstruit depuis
Git n'a pas à être sauvegardé ailleurs**. Trois catégories y échappent :

1. **Les secrets** — pour la raison exposée plus haut : l'historique est
   immuable.
2. **Les données personnelles** des artisans de l'annuaire — l'historique Git
   étant immuable, une demande d'effacement ne pourrait pas être honorée.
3. Un troisième élément, détaillé dans `docs/services/sauvegardes.md`.

Ces trois-là relèvent du stockage objet avec roulement, pas du dépôt.
