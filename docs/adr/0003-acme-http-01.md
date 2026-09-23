# 0003 — Validation ACME par HTTP-01, pas par DNS-01

**Date :** 21 septembre 2026
**État :** retenu, avec les conditions de réexamen écrites ci-dessous

## Contexte

Les certificats sont obtenus de Let's Encrypt par Caddy. Deux méthodes de
validation sont possibles.

**HTTP-01** — Let's Encrypt appelle le serveur sur le port 80. C'est ce qui
fonctionne aujourd'hui. Aucun secret n'est nécessaire.

**DNS-01** — Caddy pose un enregistrement dans la zone DNS. Cela permet des
certificats génériques (`*.exemple.fr`) et des certificats pour des noms qui
ne sont pas joignables sur le port 80.

Le DNS étant chez OVH, et les domaines des services devant être achetés chez
OVH, la zone sera la nôtre : DNS-01 est donc techniquement accessible.

## Décision

**HTTP-01.**

## Pourquoi

**L'image officielle de Caddy ne sait pas parler à l'API d'OVH.** Les
fournisseurs DNS sont des modules compilés dans le binaire. Passer à DNS-01
impose de construire et de maintenir une image Caddy maison : une chaîne de
construction de plus, à reconstruire à chaque mise à jour de Caddy et à
chaque correctif de sécurité. Sur une machine dont le principe directeur est
justement de ne rien construire — le serveur ne fait que tirer des images —
c'est une entorse coûteuse.

**Il faudrait poser sur le serveur un jeton API OVH avec droit d'écriture sur
la zone DNS.** Ce jeton permet de repointer n'importe quel domaine vers
n'importe où. Aujourd'hui, un attaquant qui prend le serveur prend le serveur ;
avec ce jeton, il prend aussi les domaines. C'est une aggravation nette du
pire scénario, en échange d'un confort.

**Les avantages de DNS-01 ne s'appliquent pas ici.** Le certificat générique
n'a pas d'objet puisque Jim a écarté les sous-domaines partagés : chaque
service a son domaine, avec un ou deux noms. Et le port 80 doit rester ouvert
de toute façon, pour la redirection vers HTTPS.

## L'argument de la transparence des certificats

Il a été soulevé et mérite d'être écrit, parce qu'il est juste.

Tout certificat émis est publié en quelques minutes dans les journaux de
transparence, qui sont publics et interrogeables. Si n8n reçoit un jour des
webhooks entrants sous un nom volontairement difficile à deviner, ce nom sera
donc **public dès l'émission de son certificat**. Le nom aléatoire protège du
devinage, pas de la découverte.

Seul un certificat générique le cacherait — puisque seul `*.exemple.fr`
apparaîtrait dans les journaux — et un certificat générique exige DNS-01.

**Cela ne change pas la décision**, pour deux raisons.

D'abord, un nom d'hôte n'est pas un secret et ne doit pas en être un. Si la
sécurité de n8n repose sur l'ignorance de son adresse, elle ne repose sur
rien : c'est l'authentification et la restriction d'accès qui la portent.

Ensuite, le coût reste le même : une image Caddy maison à maintenir, et une
clé d'API OVH en écriture sur la zone posée sur le serveur. Échanger « un nom
public » contre « un attaquant qui prend le serveur prend aussi les domaines »
est un mauvais échange.

## Quand réexaminer

Quatre situations, et aucune n'existe aujourd'hui :

1. un service qui doit être joignable en HTTPS **sans** que le port 80 soit
   ouvert ;
2. un besoin réel de certificat générique, par exemple un domaine avec des
   sous-domaines créés dynamiquement ;
3. un domaine dont le DNS pointerait ailleurs que vers ce VPS pendant qu'on
   veut malgré tout un certificat pour lui ;
4. une exigence explicite qu'un nom d'hôte n'apparaisse pas dans les journaux
   de transparence — auquel cas il faut accepter le coût ci-dessus, et se
   souvenir que cela ne dispense d'aucune autre protection.

## Conséquence opérationnelle

**Le port 80 ne se ferme jamais.** Il ne sert pas qu'à rediriger : il porte
chaque renouvellement. Le fermer produit une panne à retardement — tout
fonctionne pendant deux mois, puis les certificats expirent.
