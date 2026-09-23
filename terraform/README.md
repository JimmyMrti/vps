# Terraform — ce qui entoure le VPS

Cette couche ne crée pas le serveur. Elle tient **le DNS, le reverse DNS et la
politique de courrier** de la zone hébergée chez OVH, et publie l'IP du VPS
pour que l'inventaire Ansible n'ait pas à la recopier à la main.

Le VPS lui-même se commande depuis l'espace client OVH : le tunnel de commande
passe par un paiement que l'API ne couvre pas de bout en bout. Le décrire en
Terraform donnerait l'illusion d'une reconstruction automatique qui n'existe
pas. Le raisonnement complet est dans
[`../docs/adr/0001-terraform-et-ansible.md`](../docs/adr/0001-terraform-et-ansible.md).

---

## Le jeton d'API

À créer sur <https://api.ovh.com/createToken/>, en n'accordant **que** ces
droits — un jeton `GET/POST/PUT/DELETE` sur `/*` n'a aucune raison d'exister :

| Méthode | Chemin |
|---|---|
| `GET` | `/vps/*` |
| `GET`, `POST`, `PUT`, `DELETE` | `/domain/zone/*` |
| `GET`, `POST`, `PUT`, `DELETE` | `/ip/*/reverse` |

Mettez une date d'expiration. Puis, dans le shell — jamais dans un fichier du
dépôt :

```bash
export OVH_ENDPOINT=ovh-eu
export OVH_APPLICATION_KEY=...
export OVH_APPLICATION_SECRET=...
export OVH_CONSUMER_KEY=...
```

---

## Premier passage : importer avant d'appliquer

> **Le site est déjà en production.** Les enregistrements `A` et `AAAA` de
> l'apex existent et servent `preventioncambriolage.fr`, et depuis le
> 22/09/2026 ceux de `www` aussi. Si vous lancez
> `terraform apply` sans importer, Terraform les considère comme absents, en
> crée de nouveaux à côté, et la zone se retrouve avec des doublons — donc un
> site qui répond une fois sur deux.

Listez d'abord les identifiants des enregistrements existants :

```bash
# Nécessite le jeton ci-dessus. Renvoie les ID de la zone.
curl -s "https://eu.api.ovh.com/1.0/domain/zone/preventioncambriolage.fr/record" \
  -H "X-Ovh-Application: $OVH_APPLICATION_KEY" # ... signature complète : voir la doc OVH
```

Plus simple en pratique, l'espace client affiche chaque identifiant dans l'URL
de modification d'un enregistrement.

Puis importez, un par un. Les ressources étant indexées par domaine, la
clé fait partie de l'adresse :

```bash
terraform init
terraform import 'ovh_domain_zone_record.apex_a["preventioncambriolage.fr"]'    preventioncambriolage.fr/ID_DU_A
terraform import 'ovh_domain_zone_record.apex_aaaa["preventioncambriolage.fr"]' preventioncambriolage.fr/ID_DU_AAAA
terraform import 'ovh_domain_zone_record.www_a["preventioncambriolage.fr"]'     preventioncambriolage.fr/ID_DU_WWW_A
terraform import 'ovh_domain_zone_record.www_aaaa["preventioncambriolage.fr"]'  preventioncambriolage.fr/ID_DU_WWW_AAAA
```

Les deux dernières lignes ne valent que si `www = true` pour ce domaine, et
que si l'enregistrement `AAAA` existe — la machine peut n'avoir qu'une IPv4.
Un `terraform plan` qui propose de **créer** un enregistrement déjà présent
dans la zone est le signe qu'il manque un import, pas qu'il faut appliquer.

Et **vérifiez que le plan est vide** avant d'aller plus loin :

```bash
terraform plan
```

Un plan qui ne propose ni création ni destruction sur l'apex signifie que
l'import est correct. Tant que ce n'est pas le cas, n'appliquez pas.

---

## Régime courant

```bash
terraform plan -out=plan.tfplan
terraform apply plan.tfplan
```

Relisez toujours le plan : sur une zone DNS, une destruction est une coupure.

---

## Ce que cette couche pose

Pour **chaque** domaine déclaré dans la variable `domaines` :

| Enregistrement | Rôle |
|---|---|
| `A` / `AAAA` apex | le domaine pointe vers le VPS |
| `A` / `AAAA` www | seulement si `www = true` |
| `TXT` SPF `v=spf1 -all` | le domaine n'émet aucun courrier |
| `TXT` DMARC `p=reject` | l'usurpation est rejetée, pas seulement signalée |
| `TXT` DKIM vide | aucune clé ne signe pour ce domaine |
| `CAA` | seul Let's Encrypt peut émettre un certificat |

**Un domaine par service, et pas de sous-domaine partagé.** C'est une décision
de Jim, et elle a de bonnes raisons techniques : les politiques de sécurité de
contenu ne se mélangent pas, un nom de service n'apparaît pas dans les
journaux publics de certificats du domaine de la marque, et un service peut
être arrêté ou cédé sans toucher aux autres. Voir
[`../docs/adr/0005-un-domaine-par-service.md`](../docs/adr/0005-un-domaine-par-service.md).

Les trois enregistrements de courrier et le `CAA` sont là parce qu'un domaine
de prévention est une cible commode pour l'hameçonnage : sans eux, n'importe
qui peut écrire « au nom de » `preventioncambriolage.fr`.

> Si le domaine se met un jour à envoyer du courrier (formulaire de contact,
> notifications n8n), **ces trois enregistrements doivent être revus avant**,
> sinon les messages seront rejetés. C'est le comportement voulu : un envoi
> silencieusement non délivré est pire qu'un envoi refusé bruyamment.

---

## L'état

`terraform.tfstate` contient l'IP du serveur et la structure de la zone : il
est dans `.gitignore`. Pour une seule personne, l'état local sauvegardé avec le
poste suffit. À deux, passez à un état distant verrouillé — voir
[`backend.tf.example`](backend.tf.example), OVH Object Storage parlant S3.
