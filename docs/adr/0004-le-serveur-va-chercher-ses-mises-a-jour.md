# 0004 — Le serveur va chercher ses mises à jour, on ne les lui pousse pas

**Date :** 21 septembre 2026
**État :** retenu, repris de l'existant

## Contexte

C'est le choix structurant de l'installation d'origine, et il est conservé
tel quel. Il mérite d'être écrit parce qu'il sera tentant de le défaire : un
déploiement poussé depuis l'intégration continue est plus immédiat.

## Décision

GitHub Actions construit l'image et la publie dans son registre. Un minuteur
systemd interroge le registre toutes les dix minutes ; si l'empreinte de
l'image a changé, le service est redémarré sur la nouvelle version.

## Pourquoi

**GitHub n'a aucun accès à la machine.** Pas de clé SSH confiée à un tiers,
aucun port entrant ouvert pour le déploiement, aucun agent en écoute.

La conséquence se mesure en pire cas. Avec un déploiement poussé, un compte
GitHub compromis donne un shell sur le serveur. Avec celui-ci, il permet de
publier une mauvaise image — c'est grave, mais cela reste une image, que l'on
peut remplacer et dont on garde la trace.

**Le serveur n'héberge ni Node, ni les sources, ni chaîne de compilation.**
Uniquement Docker et des fichiers de configuration.

## Ce qui a changé par rapport à l'existant

Le script `maj.sh` d'origine était écrit pour un seul service. Il devient le
rôle `maj_service`, appelé avec le nom, le dossier et l'image — même logique,
un service quelconque.

Le détail à ne pas perdre : ce service tourne en root, et son durcissement
systemd masque `/home` **et** `/root`. Un `docker login` ordinaire écrirait
dans le dossier personnel de l'utilisateur, où root ne trouverait rien, et le
téléchargement échouerait sur « unauthorized » sans autre explication. D'où
les identifiants dans `/etc/docker/identifiants`, pointés explicitement par
`DOCKER_CONFIG`. C'est une soirée perdue si on l'ignore.

## Conséquence

Une mise en production prend jusqu'à dix minutes. Pour forcer :

```bash
sudo systemctl start maj-site.service
journalctl -u maj-site.service -n 30 --no-pager
```
