# 0001 — Terraform pour ce qui entoure le VPS, Ansible pour ce qu'il y a dedans

**Date :** 21 septembre 2026
**État :** retenu

## Contexte

Le VPS OVH existe déjà et sert `preventioncambriolage.fr` en production. Il
doit accueillir deux services de plus. L'objectif est un serveur dont l'état
se décrit et se rejoue depuis un dépôt.

## Décision

Deux outils, avec une frontière nette.

**Terraform** tient ce qui vit chez OVH et pas sur la machine : les
enregistrements DNS, le reverse DNS, la politique de courrier, les CAA.

**Ansible** tient tout ce qui vit sur la machine : paquets, comptes, SSH,
pare-feu, journalisation, Docker, frontal HTTP, services.

**Le VPS lui-même n'est décrit par aucun des deux.** Il se commande depuis
l'espace client OVH.

## Pourquoi ne pas décrire le VPS en Terraform

La tentation est réelle, et c'est précisément pour cela qu'il faut l'écarter
explicitement.

Un VPS OVH ne se commande pas entièrement par API : le tunnel de commande
passe par un paiement. Le fournisseur Terraform expose le VPS en lecture, pas
en création. Écrire une ressource qui prétendrait le créer donnerait
l'illusion d'une reconstruction automatique qui n'existe pas — et cette
illusion se paierait le jour où l'on en aurait besoin, c'est-à-dire le pire
jour possible.

Ce qui est vrai est écrit tel quel : le serveur est commandé à la main, son
contenu est reconstructible en une commande. C'est la seconde moitié qui a de
la valeur, et elle est entièrement tenue.

## Pourquoi Ansible et pas un autre outil de configuration

Ansible n'a besoin de rien sur la machine cible : ni agent, ni port ouvert,
ni compte de service. Il passe par le SSH déjà durci, avec le compte déjà
existant. Pour une machine, c'est décisif : tout autre outil aurait demandé
d'ouvrir une porte supplémentaire pour se configurer lui-même.

## Conséquences

- Perdre le VPS impose d'en recommander un à la main, puis de rejouer le
  playbook. Le chemin est documenté dans `docs/exploitation.md`.
- L'état Terraform n'est pas dans le dépôt : il contient l'IP du serveur.
- Les deux couches se parlent par une sortie Terraform reportée dans
  l'inventaire, et non par une intégration automatique — un couplage de plus
  pour une IP qui change tous les trois ans n'en vaut pas la peine.
