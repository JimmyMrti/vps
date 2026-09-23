# Données personnelles

L'annuaire est construit à partir de données publiques et de ce qu'on peut
trouver en source ouverte. **C'est précisément ce qui rend le sujet sérieux**,
et pas l'inverse : une base bâtie sur des données publiques n'est pas une base
sans obligations, c'est une base dont les obligations se voient moins.

Ce document n'est pas un avis juridique. C'est la liste de ce qui doit être
vrai dans le code et dans la configuration pour que le reste soit défendable.

---

## Les trois idées à ne pas confondre

**Public ne veut pas dire réutilisable.** Une donnée accessible à tous reste
une donnée personnelle dès qu'elle se rapporte à une personne identifiable.
Le RGPD ne prévoit aucune exception pour les données publiées : il prévoit des
règles différentes selon *qui* les a publiées et *pourquoi*. Le fait qu'une
information soit trouvable ne crée aucun droit de la collecter, de la stocker,
ni de la republier.

**L'agrégation change la nature de la donnée.** Le nom d'un artisan est public.
Son adresse est publique. Son numéro, son activité, ses chantiers, ses horaires
le sont peut-être aussi, chacun dans son coin. Rassemblés dans une fiche
consultable et interrogeable, ils forment un profil qui n'existait nulle part
avant — et c'est ce profil, pas chaque donnée prise isolément, que la
réglementation regarde. C'est aussi ce qui fait la valeur du site : on ne peut
pas revendiquer l'un et nier l'autre.

**Un entrepreneur individuel est une personne.** La moitié des artisans
français exercent en nom propre : leur raison sociale est leur nom, et
l'adresse de leur établissement est souvent leur domicile. Un annuaire
« purement professionnel » traite donc massivement des données personnelles, y
compris des adresses de domicile.

---

## La règle de collecte

Une seule, et elle est restrictive par construction :

> **N'entre dans la base que ce qui provient d'une source identifiée, dont la
> réutilisation est explicitement permise, et qui décrit l'activité
> professionnelle — pas la personne.**

Tout le reste est hors périmètre, même si c'est trouvable en dix secondes.

### Ce qui entre

| Source | Ce qu'on en tire | Réutilisation |
|---|---|---|
| Répertoire Sirene (INSEE) | SIREN/SIRET, raison sociale, adresse de l'établissement, activité (NAF), date de création | Licence Ouverte, **sous réserve du statut de diffusion** |
| Annuaire des entreprises | mêmes données, consolidées | Licence Ouverte |
| Répertoire RGE (ADEME) | qualifications, domaines de travaux | données ouvertes |
| Déclaration de l'artisan lui-même | tout le reste : téléphone, photos, description, horaires | fournie volontairement, pour cet usage |

La dernière ligne est la plus importante : **tout ce qui dépasse le registre
officiel vient de l'artisan, ou n'existe pas.** C'est ce qui fait la différence
entre un annuaire et un fichier.

### Ce qui n'entre pas

- Les données d'une unité légale marquée **non diffusible** au répertoire
  Sirene — voir plus bas, c'est la règle dure.
- Tout ce qui est aspiré d'un autre annuaire. C'est doublement fautif :
  données personnelles sans base légale d'un côté, atteinte au droit du
  producteur de base de données de l'autre (article L341-1 du code de la
  propriété intellectuelle), qui interdit l'extraction d'une partie
  substantielle d'une base tierce.
- Tout ce qui vient des réseaux sociaux : profils, publications, photos,
  relations. Publié par la personne pour un public donné, pas pour être
  reversé dans un annuaire commercial.
- Les **avis nominatifs sur une personne physique**, les mentions de litiges,
  de condamnations, de procédures. Un avis sur une entreprise est une chose ;
  sur un artisan en nom propre, c'est une donnée sur une personne, et les
  données d'infraction relèvent d'un régime à part.
- Les adresses e-mail et numéros personnels devinés, recomposés ou trouvés
  ailleurs que dans le registre ou la déclaration de l'intéressé.

Cette liste n'est pas un supplément d'âme : c'est ce qui fait la différence
entre un service qu'on peut défendre devant un artisan mécontent et un service
qu'on doit retirer.

---

## La règle dure sur les données Sirene

Le répertoire Sirene porte un indicateur `statutDiffusionUniteLegale` :

```
statutDiffusionUniteLegale = 'O'  → diffusible
statutDiffusionUniteLegale = 'P'  → nom, prénom et adresse NE SONT PAS publiés
```

Une unité marquée `P` est celle d'une personne qui **s'est explicitement
opposée** à la diffusion de ses informations. Republier ses coordonnées, c'est
défaire exactement ce qu'elle a demandé.

**Le filtre s'applique à l'import, pas à l'affichage.** Une ligne non
diffusible n'entre jamais dans la base qui sert le site public. C'est plus
strict que nécessaire, et c'est exprès : un filtre à l'affichage est contourné
tôt ou tard par un export CSV, un flux de données, une API interne devenue
publique, ou un cache.

Le script d'import **refuse de s'exécuter** si la colonne est absente du jeu de
données source. Mieux vaut un import qui échoue qu'un import qui publie ce
qu'il ne devait pas.

---

## La provenance, enregistrée donnée par donnée

C'est la mesure technique qui rend tout le reste vérifiable, et elle se décide
maintenant : la rajouter après coup sur une base déjà peuplée est impossible,
puisque l'information a été perdue à l'import.

Chaque donnée porte d'où elle vient, quand elle est arrivée, et à quel titre :

```sql
CREATE TABLE provenance (
  fiche_id    bigint      NOT NULL REFERENCES fiches(id) ON DELETE CASCADE,
  champ       text        NOT NULL,   -- 'adresse', 'telephone', 'qualifications'
  source      text        NOT NULL,   -- 'sirene', 'rge', 'declaration_artisan'
  base_legale text        NOT NULL,   -- 'interet_legitime', 'contrat', 'consentement'
  collecte_le timestamptz NOT NULL,
  PRIMARY KEY (fiche_id, champ)
);
```

Quatre choses deviennent alors possibles, qui ne le sont pas autrement :

- **Répondre à « d'où tenez-vous cela ? »** — la première question d'un artisan
  mécontent, et celle d'un contrôle. Sans provenance, la réponse honnête est
  « je ne sais pas », ce qui est la pire.
- **Retirer une source entière** si elle se révèle inutilisable, sans détruire
  le reste de la fiche.
- **Honorer un effacement pour de bon** : on sait quels champs venaient d'un
  import et reviendront au prochain, donc lesquels doivent être verrouillés.
- **Faire vivre les durées de conservation par champ**, et non par fiche.

---

## Informer les personnes, même sans les avoir contactées

Quand les données ne viennent pas de la personne elle-même, l'article 14 du
RGPD impose de l'informer — origine des données, finalité, durée, droits — dans
un délai raisonnable, **au plus tard un mois** après la collecte.

L'exemption pour « efforts disproportionnés » existe, mais elle est étroite :
elle ne dispense pas d'informer, elle autorise à le faire collectivement quand
l'information individuelle est réellement impraticable. En pratique, ici :

| Situation | Ce qu'on fait |
|---|---|
| On a une adresse e-mail professionnelle du registre | on écrit, une fois, au moment de la création de la fiche |
| On n'en a pas | mention permanente sur la fiche elle-même : origine des données, finalité, lien pour s'opposer en un clic |
| Dans tous les cas | page d'information publique décrivant les sources, et recours à l'exemption **motivé par écrit** dans le registre |

La mention sur la fiche n'est pas un détail d'interface : c'est ce qui rend
l'exemption défendable. Une fiche sans elle est une fiche qu'on ne peut pas
justifier.

---

## Droits des personnes

Il faut que ce soit **praticable**, pas seulement affiché.

| Droit | Mise en œuvre |
|---|---|
| Information | mention en pied de chaque fiche, et page dédiée |
| Opposition | formulaire en un clic depuis la fiche ; l'opposition inscrit le SIREN dans une **liste d'exclusion permanente** |
| Rectification | via la revendication de fiche, ou par le formulaire de contact |
| Effacement | suppression de la fiche + inscription dans la liste d'exclusion |
| Accès | export des données de la fiche, provenance comprise |

La liste d'exclusion est le point technique décisif. Sans elle, **le prochain
import republie ce qu'on vient de retirer**, et la personne doit redemander —
ce qui transforme un droit en boucle sans fin. La table `exclusions` est
consultée à chaque import et n'est **jamais** purgée par celui-ci.

Délai de réponse : un mois. Adresse de contact publiée dans les mentions
légales et dans `security.txt`.

---

## L'analyse d'impact est probablement obligatoire

Une AIPD est requise dès que deux des neuf critères de la CNIL sont réunis.
L'annuaire en réunit au moins deux, et peut-être trois :

| Critère | Ici |
|---|---|
| Collecte à grande échelle | oui — des centaines de milliers d'établissements |
| Croisement ou combinaison de jeux de données | oui — Sirene, RGE, déclarations |
| Évaluation ou notation | **si** le site classe, note ou recommande les artisans |

**Il vaut mieux la faire avant le lancement qu'après une plainte.** Elle force
à écrire ce que ce document esquisse — finalités, sources, durées, mesures — et
elle sert ensuite de réponse toute prête. Faite au début, c'est une journée de
travail ; faite après coup, c'est une reconstitution.

Le troisième critère est un choix produit, pas une fatalité : un annuaire qui
classe des personnes n'est pas le même objet qu'un annuaire qui les liste.

---

## Prospection

Si le site met des particuliers en relation avec des artisans, ou envoie des
messages aux artisans eux-mêmes, deux règles s'ajoutent.

**Vers les particuliers** : consentement préalable, et rien d'autre. Leurs
coordonnées sont collectées pour transmettre une demande, pas pour alimenter
une base de prospection.

**Vers les artisans** : la prospection entre professionnels reste possible sur
le fondement de l'intérêt légitime, à condition que le message porte sur leur
activité et qu'un refus soit possible et respecté dès le premier envoi.
Attention toutefois : **le numéro d'un entrepreneur individuel est souvent son
numéro personnel**, ce qui fait basculer un démarchage téléphonique dans le
régime des particuliers, et donc dans le champ de l'opposition au démarchage.
En cas de doute, le courriel plutôt que le téléphone.

---

## Durées de conservation

| Donnée | Conservée |
|---|---|
| Fiche issue des registres | tant que l'établissement est actif au répertoire, puis 12 mois |
| Fiche revendiquée, compte artisan | durée du compte, puis 12 mois |
| Demande de mise en relation | 3 ans après le dernier contact |
| Mesure d'audience | 13 mois |
| Journaux du frontal | 6 mois, 12 pour un incident constaté |
| Exécutions n8n | 7 jours |
| Sauvegardes | 7 jours / 4 semaines / 6 mois — voir [`sauvegardes.md`](sauvegardes.md) |
| **Liste d'exclusion** | **sans limite, et c'est voulu** : la purger reviendrait à republier ce qu'on a retiré |

La dernière ligne est la seule exception au principe « rien au-delà du
nécessaire », et elle se justifie par l'intérêt même de la personne : conserver
le fait qu'elle s'est opposée est ce qui protège son opposition.

---

## Registre des traitements

Obligatoire, et il vit dans le dépôt :
[`registre-traitements.md`](registre-traitements.md). Une fiche de traitement
qui n'est pas relue quand le code change ne décrit plus la réalité.

Chaque ajout de finalité impose trois gestes : mettre à jour le registre,
mettre à jour les mentions légales, et incrémenter la version du consentement
si un traceur est concerné — le mécanisme existe déjà dans le site statique.

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
données, parfois hors de l'Union européenne.

---

## Ce que la configuration garantit déjà

- Les bases de données sont sur des réseaux Docker `internal: true` : **aucune
  route vers Internet**, donc pas d'exfiltration directe.
- Les sauvegardes sont chiffrées côté client : le prestataire de stockage ne
  détient que des blocs illisibles.
- **Rien de ce qui touche aux personnes ne va dans Git.** L'historique Git est
  immuable : une donnée personnelle commitée ne se retire pas, elle se
  constate, et un effacement y serait impossible à honorer. Voir
  [`sauvegardes.md`](sauvegardes.md).
- Les exécutions n8n sont purgées à 7 jours, automatiquement.
- Les journaux du frontal sont limités en taille et en nombre : la rotation
  tient la durée de conservation par construction plutôt que par discipline.

## Ce qui reste à faire, côté application

- La table `provenance` et son alimentation à l'import. **À faire dès la
  première version** : rétroactivement, l'information est perdue.
- La table `exclusions`, consultée à chaque import.
- Le formulaire d'opposition, accessible en un clic depuis chaque fiche.
- La mention d'origine des données sur chaque fiche.
- L'export des données d'une fiche, pour le droit d'accès.
- La purge automatique des demandes de mise en relation à 3 ans.
- L'AIPD, avant le lancement public.
