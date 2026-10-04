#!/usr/bin/env bash
#
# Surveille l'occupation du disque et alerte avant qu'il soit plein.
#
# Sur une machine qui héberge des bases de données, un disque plein n'est pas
# une indisponibilité : c'est une corruption possible. PostgreSQL ne peut plus
# écrire ses journaux de transaction et s'arrête en catastrophe.
#
# 75 Go paraissent confortables jusqu'à ce que l'historique d'exécution de n8n,
# la base de l'annuaire, les images remplacées et les sauvegardes locales
# grandissent en même temps.

set -euo pipefail

SEUIL="${SEUIL_DISQUE:-80}"
OCCUPATION="$(df --output=pcent / | tail -1 | tr -dc '0-9')"

echo "Occupation de / : ${OCCUPATION} % (seuil ${SEUIL} %)"

if [ "$OCCUPATION" -lt "$SEUIL" ]; then
  exit 0
fi

# Ce qui pèse, pour que l'alerte soit exploitable sans se connecter.
echo
echo "Les plus gros postes :"
du -sh /var/lib/docker /var/sauvegardes /var/log 2>/dev/null | sort -rh
echo
echo "Volumes Docker :"
du -sh /var/lib/docker/volumes/* 2>/dev/null | sort -rh | head -10

echo
echo "Pistes, dans l'ordre :" >&2
echo "  docker image prune -a --filter 'until=168h'   # images remplacées" >&2
echo "  EXECUTIONS_DATA_MAX_AGE plus court dans services/n8n/.env" >&2
echo "  find /var/sauvegardes -name '*.dump' -mtime +3 -delete" >&2

exit 1
