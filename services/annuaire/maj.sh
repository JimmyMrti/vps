#!/usr/bin/env bash
#
# Mise à jour de l'annuaire : tire la dernière image, joue les migrations de
# schéma, puis redémarre. Dans cet ordre, et pas un autre.
#
# Le script générique du socle fait `pull` puis `up -d`. Ici cela démarrerait
# une version du code sur une base restée en arrière, ce qui casse au premier
# accès à une colonne qui n'existe pas encore. D'où cette variante.
#
# Déclenché par un minuteur systemd : le serveur va chercher ses mises à jour
# lui-même. Aucun SSH entrant, aucune clé confiée à un tiers.
#
# Idempotent : si l'image n'a pas changé, il ne se passe rien.

set -euo pipefail

DOSSIER="/opt/vps/services/annuaire"
cd "$DOSSIER"

# Identifiants du registre. Ce service tourne en root, et le durcissement
# systemd masque /home et /root : un `docker login` ordinaire y serait
# introuvable. Emplacement imposé par le socle.
export DOCKER_CONFIG="${DOCKER_CONFIG:-/etc/docker/identifiants}"

compose() { docker compose "$@"; }

# Le nom de l'image est dans .env — on le lit sans exécuter le fichier.
IMAGE="$(grep -E '^ANNUAIRE_IMAGE=' .env | head -1 | cut -d= -f2-)"
if [ -z "$IMAGE" ]; then
  echo "ANNUAIRE_IMAGE absent de $DOSSIER/.env" >&2
  exit 1
fi

# Empreinte de l'image locale portant cette étiquette.
#
# On interroge l'image et non le conteneur : après un `pull`, le conteneur
# tourne toujours sur l'ancienne version, donc le comparer ne détecterait
# jamais rien. C'est l'identifiant de l'image étiquetée qui bouge.
empreinte() {
  docker image inspect --format '{{.Id}}' "$IMAGE" 2>/dev/null || echo "absente"
}

avant="$(empreinte)"
compose pull --quiet
apres="$(empreinte)"

if [ "$avant" = "$apres" ]; then
  echo "Aucune nouvelle image ($IMAGE). Rien à faire."
  exit 0
fi

echo "Nouvelle image détectée."
echo "  avant : $avant"
echo "  après : $apres"

# -----------------------------------------------------------------------------
# Migrations, avant le redémarrage.
#
# Si elles échouent, on s'arrête ici : l'ancienne version continue de tourner
# sur une base intacte. C'est tout l'intérêt de ne pas les lancer depuis le
# conteneur applicatif.
# -----------------------------------------------------------------------------
echo "→ migrations de schéma"
if ! compose --profile migration run --rm migration; then
  echo "ÉCHEC des migrations : l'ancienne version reste en service." >&2
  exit 1
fi

echo "→ redémarrage"
compose up -d --remove-orphans

# On ne conserve pas indéfiniment les images remplacées : sur un VPS de 75 Go,
# le disque se remplit vite. Une semaine de marge permet de revenir en arrière.
docker image prune --force --filter "until=168h" >/dev/null

echo "Annuaire à jour."
