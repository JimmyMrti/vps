#!/usr/bin/env bash
#
# Exporte les workflows n8n en JSON et les commite dans un dépôt privé.
#
# Les workflows sont la valeur réelle de n8n, et ce sont des données
# structurées : elles n'ont aucune raison de vivre uniquement dans une base sur
# une machine. Dans Git, on gagne l'historique, la comparaison d'une version à
# l'autre, et la restauration d'un seul workflow sans toucher au reste.
#
# Ce que ce script n'exporte JAMAIS : les identifiants. La commande qui les
# sortirait existe ; elle n'est pas utilisée ici et ne doit pas l'être.
#
# Voir docs/services/sauvegardes.md.

set -euo pipefail

DEPOT="${DEPOT_WORKFLOWS:-/var/sauvegardes/workflows-n8n}"
COMPOSE="/opt/vps/services/n8n/docker-compose.yml"
EXPORT="$DEPOT/workflows"

[ -d "$DEPOT/.git" ] || {
  echo "Dépôt absent : $DEPOT" >&2
  echo "Le créer une fois : git clone <dépôt privé dédié> $DEPOT" >&2
  exit 1
}

# -----------------------------------------------------------------------------
# Export.
#
# --separate donne un fichier par workflow : c'est ce qui rend l'historique
# lisible. Un fichier unique produirait un diff illisible à chaque changement.
# -----------------------------------------------------------------------------
rm -rf "$EXPORT"
mkdir -p "$EXPORT"

docker compose -f "$COMPOSE" exec -T n8n \
  n8n export:workflow --all --separate --output=/tmp/export >/dev/null

docker compose -f "$COMPOSE" cp n8n:/tmp/export/. "$EXPORT/"
docker compose -f "$COMPOSE" exec -T n8n rm -rf /tmp/export

# -----------------------------------------------------------------------------
# Filet de sécurité avant de commiter.
#
# L'historique Git est immuable : un secret ou une donnée personnelle commités
# ici n'en ressortent pas. Mieux vaut un export qui échoue qu'un jeton publié
# pour toujours dans un historique, même privé.
# -----------------------------------------------------------------------------
MOTIFS_SECRET='(gh[pousr]_[A-Za-z0-9]{16,}|sk-[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16}|xox[baprs]-[A-Za-z0-9-]{10,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\.)'

if grep -rEl "$MOTIFS_SECRET" "$EXPORT" 2>/dev/null | grep -q .; then
  echo "ARRÊT : un motif de jeton a été trouvé dans les workflows exportés." >&2
  grep -rEl "$MOTIFS_SECRET" "$EXPORT" >&2
  echo >&2
  echo "Sortir ce secret du workflow et le mettre dans un identifiant n8n," >&2
  echo "puis relancer. Rien n'a été commité." >&2
  exit 1
fi

# Les adresses e-mail ne bloquent pas — elles sont parfois légitimes dans un
# nom de workflow — mais elles sont signalées : dans un historique immuable,
# une adresse commitée ne se retire plus.
ADRESSES="$(grep -rhoE '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' "$EXPORT" 2>/dev/null | sort -u || true)"
if [ -n "$ADRESSES" ]; then
  echo "Adresses e-mail présentes dans les workflows exportés :" >&2
  echo "$ADRESSES" | sed 's/^/  /' >&2
  echo "  → les déplacer vers un identifiant ou une variable." >&2
fi

# -----------------------------------------------------------------------------
# Commit.
#
# Rien à commiter est le cas normal : aucun workflow n'a changé depuis hier.
# -----------------------------------------------------------------------------
cd "$DEPOT"
git add -A workflows

if git diff --cached --quiet; then
  echo "Aucun changement de workflow."
  exit 0
fi

RESUME="$(git diff --cached --name-status | head -20)"
git -c user.name="Sauvegarde VPS" -c user.email="sauvegarde@localhost" \
  commit -q -m "Workflows n8n au $(date +%Y-%m-%d)" -m "$RESUME"

git push -q origin HEAD
echo "Workflows poussés."
