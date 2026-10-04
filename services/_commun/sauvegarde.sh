#!/usr/bin/env bash
#
# Sauvegarde quotidienne des données qui n'existent que sur cette machine.
#
# Déroulé : vidage logique des bases, puis restic vers le stockage objet. Les
# fichiers restent trois jours en local pour une restauration immédiate, et
# partent chiffrés pour tout le reste.
#
# Ce script ne purge rien : les identifiants S3 présents sur le VPS n'ont pas
# le droit de supprimer. Un rançongiciel qui prend la machine ne peut donc pas
# effacer les sauvegardes. La purge se lance à la main depuis le poste de
# l'administrateur, avec un second jeu d'identifiants.
#
# Voir docs/services/sauvegardes.md.

set -euo pipefail

SPOOL="/var/sauvegardes"
SERVICES="/opt/vps/services"
HORODATAGE="$(date +%Y-%m-%dT%H%M%S)"

# RESTIC_REPOSITORY, RESTIC_PASSWORD_FILE, AWS_ACCESS_KEY_ID et
# AWS_SECRET_ACCESS_KEY viennent de /opt/vps/secrets/sauvegarde/restic.env,
# chargé par l'unité systemd. Rien de tout cela n'est écrit ici.
: "${RESTIC_REPOSITORY:?RESTIC_REPOSITORY manquant — vérifier restic.env}"

install -d -m 0700 "$SPOOL"

# -----------------------------------------------------------------------------
# Vidage des bases.
#
# On ne copie pas les fichiers de PostgreSQL : copier une base en cours
# d'écriture produit une sauvegarde qui restaure parfois, et on l'apprend le
# jour où elle ne restaure pas. Un pg_dump est cohérent par construction.
# -----------------------------------------------------------------------------
vider_base() {
  local service="$1" conteneur="$2" utilisateur="$3" base="$4"
  local sortie="$SPOOL/${service}-${HORODATAGE}.dump"

  echo "→ vidage de $base ($service)"
  docker compose -f "$SERVICES/$service/docker-compose.yml" exec -T "$conteneur" \
    sh -c "PGPASSWORD=\$(cat /run/secrets/mdp_postgres) pg_dump -h 127.0.0.1 -U $utilisateur -Fc $base" \
    > "$sortie.partiel"

  # Renommage seulement en cas de succès : un fichier `.dump` présent est un
  # fichier complet. Sans cela, une coupure laisse un vidage tronqué qui a
  # l'air valide.
  mv "$sortie.partiel" "$sortie"
  chmod 600 "$sortie"
}

vider_base n8n      n8n-db      n8n      n8n
vider_base annuaire annuaire-db annuaire annuaire

# -----------------------------------------------------------------------------
# Volumes à sauvegarder tels quels.
#
# n8n_donnees contient la configuration de n8n. La clé de chiffrement, elle,
# est dans /opt/vps/secrets/ et doit vivre AUSSI hors du serveur : une
# sauvegarde de la base n8n sans cette clé ne vaut rien.
# -----------------------------------------------------------------------------
chemins_volumes() {
  local volume chemin
  for volume in n8n_n8n_donnees n8n_n8n_fichiers annuaire_annuaire_fichiers; do
    if chemin="$(docker volume inspect -f '{{ .Mountpoint }}' "$volume" 2>/dev/null)"; then
      echo "$chemin"
    else
      echo "volume absent, ignoré : $volume" >&2
    fi
  done
}

mapfile -t VOLUMES < <(chemins_volumes)

# -----------------------------------------------------------------------------
# Envoi.
# -----------------------------------------------------------------------------
echo "→ envoi vers $RESTIC_REPOSITORY"
restic backup \
  --tag quotidienne \
  --host vps-ovh \
  "$SPOOL" \
  /opt/vps/secrets \
  "${VOLUMES[@]}"

# -----------------------------------------------------------------------------
# Ménage local. Trois jours : de quoi restaurer sans attendre un
# téléchargement, pas de quoi remplir le disque.
# -----------------------------------------------------------------------------
find "$SPOOL" -name '*.dump' -mtime +3 -delete
find "$SPOOL" -name '*.partiel' -mtime +1 -delete

echo "Sauvegarde terminée."
