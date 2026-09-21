# Reprendre le site en production sans le couper

À lire **avant** de jouer le playbook sur la machine de production.

Le site tourne. Il a ses conteneurs, son Caddy, ses certificats. Le socle
décrit une organisation différente, et la bascule de l'une à l'autre est le
seul moment vraiment risqué de tout ce chantier.

---

## Ce qui change exactement

| Aujourd'hui | Après |
|---|---|
| `/opt/preventioncambriolage/` | `/opt/vps/site/` |
| Le site embarque son propre Caddy | Un frontal mutualisé, partagé avec n8n et l'annuaire |
| Volume `caddy_data` de la pile du site | Volume `frontal_certificats` |
| Fichiers déposés par `scp` | Fichiers écrits par Ansible |
| Réseau `site` | Réseau `edge` |
| Conteneur `web` | Conteneur `web` *(inchangé)* |
| `ufw` | `nftables` + chaîne `DOCKER-USER` |

Ce qui **ne** change **pas** : l'image du site, son contenu, sa configuration
nginx, sa chaîne de construction, et le fait que le serveur va chercher ses
mises à jour.

---

## Les deux pièges

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

---

## Procédure

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
  -v preventioncambriolage_caddy_data:/source:ro \
  -v /root:/cible alpine \
  tar czf /cible/certificats-avant-bascule.tgz -C /source .
```

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
cd /opt/preventioncambriolage
docker compose -f docker-compose.prod.yml down

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

### Étape 7 — Nettoyer, plus tard

**Pas le même jour.** Laissez l'ancienne pile en place, arrêtée, quelques
jours : c'est le retour arrière le plus rapide qui existe.

```bash
# Une fois la confiance établie, et pas avant :
docker volume rm preventioncambriolage_caddy_data
sudo rm -rf /opt/preventioncambriolage
```

Remettre `ttl = 3600`.

---

## Retour arrière

Tant que l'étape 7 n'est pas faite :

```bash
cd ~/vps && ansible-playbook site.yml --tags proxy --extra-vars "proxy_arret=true"
docker compose -f /opt/vps/frontal/compose.yml down

cd /opt/preventioncambriolage
docker compose -f docker-compose.prod.yml up -d
```

Le site repart sur ses anciens certificats, qui sont toujours valides.
