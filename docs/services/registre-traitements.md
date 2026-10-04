# Registre des traitements

Document vivant, à relire à chaque évolution fonctionnelle. Responsable de
traitement : l'éditeur du site. Coordonnées de contact à compléter.

---

## 1 — Annuaire des artisans

| | |
|---|---|
| **Finalité** | publier un annuaire d'artisans permettant à un particulier de trouver un professionnel |
| **Personnes concernées** | artisans, y compris entrepreneurs individuels |
| **Données** | raison sociale, SIREN/SIRET, adresse de l'établissement, activité (NAF), qualifications, coordonnées professionnelles |
| **Source** | répertoire Sirene (INSEE), répertoire RGE (ADEME), annuaire des entreprises, déclaration de l'artisan. **Aucune autre** : ni aspiration d'annuaires tiers, ni réseaux sociaux, ni recomposition de coordonnées |
| **Base légale** | intérêt légitime — information du public sur une offre professionnelle |
| **Conservation** | tant que l'établissement est actif au répertoire, puis 12 mois |
| **Destinataires** | public (site), hébergeur |
| **Transferts hors UE** | aucun |
| **Information des personnes** | article 14 : courriel à la création de la fiche quand une adresse professionnelle est connue, sinon mention permanente sur la fiche avec l'origine des données et le lien d'opposition. Recours à l'exemption pour efforts disproportionnés motivé par écrit |
| **Mesures** | filtrage `statutDiffusionUniteLegale` à l'import ; provenance enregistrée champ par champ (source, base légale, date) ; liste d'exclusion permanente consultée à chaque import ; base sur réseau interne sans route vers Internet |
| **AIPD** | requise — au moins deux critères CNIL réunis (collecte à grande échelle, croisement de jeux de données), un troisième si le site note ou classe les artisans. À réaliser **avant** le lancement public |

## 2 — Comptes artisans (revendication de fiche)

| | |
|---|---|
| **Finalité** | permettre à un artisan de corriger et enrichir sa fiche |
| **Personnes concernées** | artisans inscrits |
| **Données** | e-mail, mot de passe haché (argon2id), téléphone, contenus publiés |
| **Base légale** | exécution du contrat (conditions d'utilisation) |
| **Conservation** | durée du compte, puis 12 mois |
| **Destinataires** | public pour les contenus publiés, hébergeur |
| **Transferts hors UE** | aucun |
| **Mesures** | mot de passe haché, vérification de l'adresse e-mail, journalisation des connexions |

## 3 — Mise en relation

| | |
|---|---|
| **Finalité** | transmettre une demande de devis d'un particulier à un artisan |
| **Personnes concernées** | particuliers demandeurs |
| **Données** | nom, e-mail, téléphone, code postal, description du besoin |
| **Base légale** | consentement |
| **Conservation** | 3 ans après le dernier contact |
| **Destinataires** | l'artisan destinataire, hébergeur, service d'envoi d'e-mails |
| **Transferts hors UE** | selon le service d'envoi retenu — à trancher avant mise en service |
| **Mesures** | purge automatique à 3 ans, pas de conservation dans l'historique n8n au-delà de 7 jours |

## 4 — Mesure d'audience

| | |
|---|---|
| **Finalité** | mesurer la fréquentation |
| **Données** | identifiants de mesure, parcours |
| **Base légale** | consentement, recueilli par le bandeau existant |
| **Conservation** | 13 mois |
| **Destinataires** | Google |
| **Transferts hors UE** | oui — États-Unis |
| **Mesures** | aucun script chargé avant consentement, suppression effective des cookies au retrait |

## 5 — Journaux techniques

| | |
|---|---|
| **Finalité** | sécurité, diagnostic d'incident |
| **Données** | adresse IP, URL, agent utilisateur, horodatage |
| **Base légale** | intérêt légitime — sécurité du système d'information |
| **Conservation** | 6 mois, 12 mois pour les journaux liés à un incident constaté |
| **Destinataires** | administrateur |
| **Transferts hors UE** | aucun |
| **Mesures** | rotation par taille et par nombre de fichiers, accès réservé à l'administrateur |

## 6 — Automatisation (n8n)

| | |
|---|---|
| **Finalité** | exécuter des traitements automatisés au service des finalités ci-dessus |
| **Données** | celles des traitements qu'il sert |
| **Base légale** | celle du traitement d'origine |
| **Conservation** | historique d'exécution purgé à 7 jours |
| **Destinataires** | **les services tiers appelés par chaque workflow — à recenser ici au fil de leur ajout** |
| **Transferts hors UE** | dépend des services appelés |
| **Mesures** | interface non exposée publiquement, identifiants chiffrés, purge automatique |
