# 0005 — Un domaine par service, aucun sous-domaine partagé

**Date :** 21 septembre 2026
**État :** retenu — décision de Jim

## Contexte

Trois services vont cohabiter sur la même machine. La solution évidente était
de les mettre sous `preventioncambriolage.fr` : `n8n.`, `annuaire.`. Elle a
été écartée.

## Décision

Chaque service a **son propre domaine**, acheté chez OVH.

Le nom générique du VPS (`vpsXXXXXX.ovh.net`) a été envisagé pour n8n, puis
écarté lui aussi.

## Pourquoi pas de sous-domaine

**Les journaux de certificats sont publics.** Chaque certificat émis est
inscrit dans les registres de transparence, consultables par tout le monde.
Un `n8n.preventioncambriolage.fr` annonce donc publiquement qu'un n8n tourne
derrière cette marque, à qui veut le lire — y compris à qui cherche des
instances n8n mal protégées.

**Les politiques de sécurité de contenu ne se mélangent pas.** Le site
statique a une CSP stricte, qui interdit tout script en ligne, et elle doit le
rester. L'annuaire en aura une plus large. Deux politiques inconciliables sur
le même domaine finissent toujours par un alignement sur la plus permissive.

**Le HSTS du site couvre ses sous-domaines.** Il est envoyé avec
`includeSubDomains` et `preload` : tout sous-domaine doit être en HTTPS
valide dès la première requête d'un navigateur, y compris pour un essai. Cela
interdit en pratique d'éprouver un nouveau service dans un navigateur avec un
certificat de test, puisque HSTS supprime l'avertissement contournable.

**Un service peut être arrêté, vendu ou déplacé** sans toucher au domaine des
autres.

## Pourquoi pas le nom générique du VPS

`ovh.net` n'est pas dans la *Public Suffix List*. Pour Let's Encrypt, tous les
`vpsXXXXXX.ovh.net` relèvent donc du même plafond d'émission : le quota est
partagé avec les autres clients d'OVH, et peut être épuisé par des tiers.
Par ailleurs la zone n'est pas la nôtre — nous ne pouvons rien y prouver ni
rien y corriger.

## Conséquence

Tant qu'un domaine n'est pas acheté, le service correspondant est monté mais
**pas joignable publiquement** : son fichier de site retombe sur un nom en
`.localhost`, pour lequel Caddy fabrique un certificat interne sans rien
demander à Let's Encrypt. C'est le bon état par défaut — un service en attente
de domaine ne doit pas être ouvert par accident.
