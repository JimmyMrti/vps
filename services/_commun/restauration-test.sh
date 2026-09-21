#!/usr/bin/env bash
#
# Restauration d'essai, mensuelle.
#
# Une sauvegarde qu'on n'a jamais restaurée n'est pas une sauvegarde, c'est une
# croyance. Ce script ne se contente pas de vérifier que les fichiers sont
# lisibles : il restaure réellement le dernier vidage dans un PostgreSQL
# jetable et compte les lignes. Une sauvegarde qui restaure une base vide
# passerait tous les contrôles d'intégrité et ne vaudrait rien.
#
# Sort en erreur si le compte est sous le seuil, ce qui déclenche l'alerte
# systemd. Voir docs/services/sauvegardes.md.

set -euo pipefail

BASE="${1:-n8n}"            # n8n | annuaire
SEUIL="${2:-1}"             # nombre de lignes minimum attendu
TRAVAIL="$(mktemp -d /tmp/restauration-test.XXXXXX)"
CONTENEUR="restauration-test-$$"

nettoyer() {
  docker rm -f "$CONTENEUR" >/dev/null 2>&1 || true
  rm -rf "$TRAVAIL"
}
trap nettoyer EXIT

echo "→ récupération du dernier vidage de $BASE"
restic restore latest --target "$TRAVAIL" --include "/var/sauvegardes/${BASE}-*.dump"

DUMP="$(find "$TRAVAIL" -name "${BASE}-*.dump" | sort | tail -1)"
[ -n "$DUMP" ] || { echo "aucun vidage de $BASE dans la sauvegarde" >&2; exit 1; }
echo "  vidage retenu : $(basename "$DUMP")"

echo "→ PostgreSQL jetable"
docker run -d --name "$CONTENEUR" \
  -e POSTGRES_PASSWORD=essai \
  -e POSTGRES_DB="$BASE" \
  -e POSTGRES_USER="$BASE" \
  postgres:16-alpine >/dev/null

for _ in $(seq 1 30); do
  docker exec "$CONTENEUR" pg_isready -U "$BASE" >/dev/null 2>&1 && break
  sleep 2
done

echo "→ restauration"
docker exec -i "$CONTENEUR" pg_restore -U "$BASE" -d "$BASE" --no-owner < "$DUMP"

echo "→ comptage"
# ANALYZE d'abord : juste après un pg_restore, les statistiques du planificateur
# sont vides et pg_stat_user_tables renverrait zéro sur une base pourtant
# pleine. On mesurerait un faux échec.
docker exec "$CONTENEUR" psql -U "$BASE" -d "$BASE" -qc 'ANALYZE;' >/dev/null
LIGNES="$(docker exec "$CONTENEUR" psql -U "$BASE" -d "$BASE" -tAc "
  SELECT COALESCE(SUM(n_live_tup), 0)
  FROM pg_stat_user_tables;
")"
echo "  lignes restaurées : $LIGNES (seuil : $SEUIL)"

if [ "$LIGNES" -lt "$SEUIL" ]; then
  echo "ÉCHEC : la base restaurée est vide ou presque." >&2
  exit 1
fi

echo "Restauration d'essai réussie pour $BASE."
