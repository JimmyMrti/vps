#!/usr/bin/env bash
#
# Signale l'échec d'une unité systemd.
#
# Sans alerte, un contrôle de sauvegarde ne sert à rien : personne ne lit un
# journal qui va bien, et on découvre la panne le jour où on a besoin de
# restaurer.
#
# Appelé par `OnFailure=alerte@%n.service`.

set -uo pipefail

UNITE="${1:?unité manquante}"
EXTRAIT="$(journalctl -u "$UNITE" -n 30 --no-pager 2>/dev/null || echo 'journal illisible')"

# Toujours dans le journal, quoi qu'il arrive : c'est la trace qui reste même
# si l'envoi échoue.
logger -t alerte -p daemon.err "ÉCHEC de $UNITE"

if [ -z "${ALERTE_WEBHOOK:-}" ]; then
  echo "ALERTE_WEBHOOK non défini : alerte seulement journalisée." >&2
  exit 0
fi

# Le webhook peut être un workflow n8n. Limite à connaître : si c'est n8n qui
# est en panne, l'alerte ne part pas. Pour les sauvegardes, un service externe
# de surveillance (appel périodique attendu, alerte si absent) est le seul
# dispositif qui ne dépende pas de la machine surveillée.
curl --silent --show-error --fail --max-time 20 \
  --header 'Content-Type: application/json' \
  --data "$(jq -Rn --arg u "$UNITE" --arg j "$EXTRAIT" \
      '{unite: $u, machine: "vps-ovh", journal: $j}')" \
  "$ALERTE_WEBHOOK" \
  || { echo "envoi de l'alerte impossible" >&2; exit 1; }
