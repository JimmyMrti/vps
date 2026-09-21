# Données personnelles

Le site statique actuel ne collecte rien d'autre qu'une mesure d'audience
soumise à consentement. **L'annuaire et n8n changent de catégorie :** l'un
publie des données sur des personnes, l'autre fait transiter des données de
visiteurs.

Ce document n'est pas un avis juridique. C'est la liste de ce qui doit être
vrai dans le code et dans la configuration pour que le reste soit défendable.

---

## Ce qui est traité, et pourquoi

| Traitement | Données | Base légale retenue | Conservation |
|---|---|---|---|
| Fiches d'artisans | raison sociale, SIREN, adresse professionnelle, activité, qualifications | intérêt légitime — publier un annuaire professionnel | tant que l'établissement est actif au répertoire, puis 12 mois |
| Fiches revendiquées | compte, e-mail, téléphone, contenus ajoutés | contrat — l'artisan gère sa fiche | durée du compte, puis 12 mois |
| Mise en relation | nom, e-mail, téléphone, description du besoin | consentement du particulier | 3 ans après le dernier contact |
| Mesure d'audience | identifiants de mesure | consentement | 13 mois |
| Journaux du frontal | adresses IP, URL, agent utilisateur | intérêt légitime — sécurité | 6 mois, 12 pour un incident |
| Exécutions n8n | ce que les workflows manipulent | suit le traitement d'origine | 7 jours |

**Le point qui surprend le plus :** les données d'un entrepreneur individuel
sont des données personnelles. Une entreprise unipersonnelle, c'est une
personne, dont le nom et souvent l'adresse du domicile constituent l'adresse de
l'établissement. Un annuaire d'artisans est donc un traitement de données
personnelles, même s'il ne contient « que » des professionnels.

---

## La règle dure sur les données Sirene

Le répertoire Sirene porte `statutDiffusionUniteLegale`. Une unité marquée `P`
est **partiellement diffusible** : la personne s'est opposée à la diffusion de
ses informations.

```
statutDiffusionUniteLegale = 'O'  → diffusible
statutDiffusionUniteLegale = 'P'  → nom, prénom et adresse NE SONT PAS publiés
```

**Le filtre s'applique à l'import, pas à l'affichage.** Une ligne non
diffusible n'entre jamais dans la base qui sert le site public. C'est plus
strict que nécessaire, et c'est exprès : un filtre à l'affichage est contourné
tôt ou tard par un export CSV, un flux de données, une API interne devenue
publique, ou un cache.

Le script d'import refuse de s'exécuter si la colonne est absente du jeu de
données source. Mieux vaut un import qui échoue qu'un import qui publie ce
qu'il ne devait pas.

**Ce que l'annuaire ne collecte pas**, quoi qu'il arrive : le téléphone
personnel obtenu autrement que par l'artisan lui-même, les avis nominatifs sur
une personne physique, toute donnée aspirée sur un autre annuaire — qui serait
à la fois une donnée personnelle sans base légale et une atteinte au droit du
producteur de base de données.

---

## Droits des personnes

Il faut que ce soit **praticable**, pas seulement affiché.

| Droit | Mise en œuvre |
|---|---|
| Information | mention en pied de chaque fiche : origine des données, finalité, comment s'y opposer |
| Opposition | formulaire dédié ; l'opposition inscrit l'identifiant SIREN dans une **liste d'exclusion permanente** |
| Rectification | via la revendication de fiche, ou par le formulaire de contact |
| Effacement | suppression de la fiche + inscription dans la liste d'exclusion |

La liste d'exclusion est le point technique important. Sans elle, le prochain
import de la base Sirene **republie ce qu'on vient de retirer**, et la personne
doit redemander. La table `exclusions` est consultée à chaque import et n'est
jamais purgée par celui-ci.

Délai de réponse : un mois. Adresse de contact à publier dans les mentions
légales et dans le `security.txt`.

---

## Registre des traitements

Obligatoire dès qu'on traite autre chose que de façon occasionnelle. Il vit
dans le dépôt, en [`registre-traitements.md`](registre-traitements.md), et non
dans un classeur oublié : une fiche de traitement qui n'est pas relue quand le
code change ne décrit plus la réalité.

Chaque ajout de finalité impose trois gestes, pas un : mettre à jour le
registre, mettre à jour les mentions légales, et incrémenter la version du
consentement si un traceur est concerné — le mécanisme existe déjà dans le site
statique (`site/src/lib/consentement.ts`).

---

## Sous-traitants et hébergement

| Qui | Rôle | Où |
|---|---|---|
| OVH | hébergeur du VPS | France |
| OVH Object Storage | sauvegardes chiffrées | France, région distincte |
| GitHub (GHCR) | registre d'images | États-Unis — **images uniquement, aucune donnée personnelle** |
| Google Analytics | mesure d'audience | hors UE, soumis au consentement, déjà en place |

**Chaque service tiers appelé par un workflow n8n devient un sous-traitant** et
doit entrer dans ce tableau. C'est la conséquence la moins anticipée de
l'installation de n8n : brancher un workflow sur un service d'envoi d'e-mails
ou sur un outil d'intelligence artificielle, c'est ajouter un destinataire de
données, parfois hors de l'Union européenne. Le tableau doit être tenu à jour
en même temps que les workflows.

---

## Ce que la configuration garantit déjà

- Les bases de données sont sur des réseaux Docker `internal: true` : **aucune
  route vers Internet**, donc pas d'exfiltration directe.
- Les sauvegardes sont chiffrées côté client : le prestataire de stockage ne
  détient que des blocs illisibles.
- Les exécutions n8n sont purgées à 7 jours, automatiquement.
- Les journaux du frontal sont limités en taille et en nombre de fichiers ; la
  rotation les fait disparaître, ce qui remplit l'obligation de durée par
  construction plutôt que par discipline.

## Ce qui reste à faire, côté application

- Le formulaire d'opposition et la table `exclusions`.
- La mention d'origine des données sur chaque fiche.
- La purge automatique des demandes de mise en relation à 3 ans.
- L'anonymisation des adresses IP dans les journaux applicatifs, s'il y en a.
