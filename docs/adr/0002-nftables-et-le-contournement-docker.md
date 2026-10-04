# 0002 — nftables, et le filet qui rattrape le contournement par Docker

**Date :** 21 septembre 2026
**État :** retenu

## Contexte

L'installation d'origine utilisait `ufw` avec trois ports ouverts, et sa
documentation signalait déjà le piège : **Docker contourne le pare-feu**.

Ce n'est pas une approximation. Quand un conteneur publie un port, Docker
écrit lui-même une règle de traduction d'adresse et une règle d'acceptation
directement dans netfilter. Ces règles sont évaluées **avant** celles de
l'hôte. Un `ports: "5678:5678"` ajouté sans y penser dans un fichier compose
rend le service joignable depuis l'Internet entier, pendant que `ufw status`
continue d'afficher trois ports ouverts et un serveur bien tenu.

Tant qu'il n'y avait qu'un site statique et un frontal, la règle « ne publiez
que 80 et 443 » suffisait. Avec n8n et l'annuaire, chacun avec sa base de
données, cette règle repose sur la vigilance de la personne qui écrit le
prochain fichier compose. Un an plus tard, à 23 h, en cherchant pourquoi un
service ne répond pas, cette personne ajoutera un `ports:` pour déboguer.

## Décision

Deux étages, et il faut les deux.

**Étage 1 — `nftables` pour le trafic destiné à l'hôte.** Politique d'entrée
en rejet, quatre ouvertures, limitation de débit sur les nouvelles connexions
SSH. `ufw` est retiré : le faire cohabiter avec nftables produit un jeu de
règles que personne ne sait plus lire.

**Étage 2 — la chaîne `DOCKER-USER` pour le trafic destiné aux conteneurs.**
Docker réserve cette chaîne à l'administrateur, la traverse avant ses propres
règles d'acceptation, et ne l'efface jamais. On y refuse tout ce qui vient de
l'interface publique, sauf vers 80 et 443. Une unité systemd la repose après
chaque démarrage du démon Docker, qui reconstruit ses chaînes.

## Ce que cela change concrètement

Un `ports:` ajouté par mégarde n'ouvre plus rien vers l'extérieur. Le service
reste joignable depuis l'hôte et depuis les autres conteneurs, donc le
débogage fonctionne ; il n'est simplement plus exposé à l'Internet.

La bonne pratique ne change pas — **aucune application ne publie de port** —
mais elle cesse d'être la seule ligne de défense.

## Conséquence à connaître

Un bannissement `fail2ban` posé dans la chaîne d'entrée de l'hôte n'arrête pas
le trafic vers un conteneur : ce trafic passe par les chaînes de Docker.
Bannir une adresse qui attaque un site servi par le frontal exige donc une
action visant `DOCKER-USER`. La jail `sshd` du socle, elle, vise bien l'hôte
et la chaîne d'entrée est la bonne cible.
