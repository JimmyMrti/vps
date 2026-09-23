#!/usr/bin/env bash
#
# Fournit le mot de passe du coffre ansible-vault, sur la sortie standard.
#
# Ce fichier est versionné ; le mot de passe, lui, ne l'est jamais. Adaptez la
# source à votre outil : les deux premières sont données à titre d'exemple.

set -euo pipefail

# 1. Variable d'environnement — pratique en intégration continue.
if [ -n "${ANSIBLE_VAULT_PASSWORD:-}" ]; then
  printf '%s' "$ANSIBLE_VAULT_PASSWORD"
  exit 0
fi

# 2. Fichier local, hors dépôt (il est dans .gitignore).
if [ -f "$HOME/.config/vps/coffre" ]; then
  cat "$HOME/.config/vps/coffre"
  exit 0
fi

# 3. Gestionnaire de mots de passe. Décommentez la ligne qui correspond.
#
# if command -v pass >/dev/null; then exec pass show vps/coffre; fi
# if command -v op   >/dev/null; then exec op read "op://Perso/vps-coffre/password"; fi
# if command -v bw   >/dev/null; then exec bw get password vps-coffre; fi

cat >&2 <<'AIDE'
Mot de passe du coffre introuvable.

Trois possibilites :
  export ANSIBLE_VAULT_PASSWORD='...'
  echo '...' > ~/.config/vps/coffre && chmod 600 ~/.config/vps/coffre
  decommenter la ligne de votre gestionnaire dans scripts/coffre-mot-de-passe.sh

Voir docs/secrets.md.
AIDE
exit 1
