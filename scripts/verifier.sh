#!/usr/bin/env bash
#
# Contrôles du dépôt, avant de pousser. Aucun ne touche au serveur.
#
#   ./scripts/verifier.sh
#
# Chaque contrôle est facultatif : s'il manque l'outil, il est signalé et
# ignoré plutôt que de faire échouer l'ensemble.

set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

# ansible-lint et ansible-playbook sont lances depuis la racine du depot, alors
# que ansible.cfg (et donc collections_path) vit dans ansible/. Sans cette
# ligne, chaque module d'une collection est signale comme introuvable.
#
# Le chemin par defaut est conserve derriere : exporter la variable la
# REMPLACE au lieu de s'y ajouter, et une installation faite par
# `ansible-galaxy` sans -p atterrit dans ~/.ansible/collections, qui
# deviendrait alors invisible.
export ANSIBLE_COLLECTIONS_PATH="$PWD/ansible/collections:${HOME}/.ansible/collections"
# Les controles ne dechiffrent rien, mais Ansible refuse un fichier de mot de
# passe vide : on lui en fournit un factice.
#
# Si un coffre chiffre est present dans group_vars, il faut en revanche le vrai
# mot de passe — exportez ANSIBLE_VAULT_PASSWORD avant de lancer ce script.
if [ -z "${ANSIBLE_VAULT_PASSWORD_FILE:-}" ]; then
  COFFRE_FACTICE="$(mktemp)"
  trap 'rm -f "$COFFRE_FACTICE"' EXIT
  printf '%s' "${ANSIBLE_VAULT_PASSWORD:-controles-sans-dechiffrement}" > "$COFFRE_FACTICE"
  export ANSIBLE_VAULT_PASSWORD_FILE="$COFFRE_FACTICE"
fi

echec=0
lance() {
  local titre="$1"; shift
  printf '\n\033[1m== %s ==\033[0m\n' "$titre"
  if "$@"; then
    printf '\033[32m  ok\033[0m\n'
  else
    printf '\033[31m  echec\033[0m\n'
    echec=1
  fi
}
absent() { printf '\n\033[33m== %s : outil absent, ignore ==\033[0m\n' "$1"; }

# --- YAML -------------------------------------------------------------------
if command -v yamllint >/dev/null; then
  lance "yamllint" yamllint ansible/
else
  absent "yamllint"
fi

# --- Ansible ----------------------------------------------------------------
if command -v ansible-lint >/dev/null; then
  lance "ansible-lint" ansible-lint ansible/
else
  absent "ansible-lint"
fi

if command -v ansible-playbook >/dev/null; then
  # --syntax-check n'exige ni connexion ni coffre.
  lance "syntaxe des playbooks" \
    ansible-playbook --syntax-check \
      -i ansible/inventaire/production.yml \
      ansible/site.yml ansible/durcissement.yml ansible/verification.yml
else
  absent "ansible-playbook"
fi

# --- Terraform --------------------------------------------------------------
if command -v terraform >/dev/null; then
  lance "terraform fmt" terraform -chdir=terraform fmt -check -recursive
  lance "terraform validate" bash -c \
    'terraform -chdir=terraform init -backend=false >/dev/null && terraform -chdir=terraform validate'
else
  absent "terraform"
fi

# --- Scripts shell ----------------------------------------------------------
if command -v shellcheck >/dev/null; then
  lance "shellcheck" bash -c 'shellcheck scripts/*.sh'
else
  absent "shellcheck"
fi

# --- Gabarits Jinja ---------------------------------------------------------
# Un gabarit dont la syntaxe est cassee ne se voit qu'au deploiement, c'est-a-
# dire au pire moment. On l'attrape ici.
if python3 -c 'import jinja2' 2>/dev/null; then
  lance "syntaxe des gabarits" python3 scripts/verifier-gabarits.py
else
  absent "jinja2"
fi

# --- Aucun secret en clair --------------------------------------------------
#
# Un coffre commite en clair est le genre d'accident qui ne se repare pas :
# l'historique Git est immuable, et le secret y reste lisible.
# shellcheck disable=SC2317  # appelee indirectement, via `lance`
verifier_coffre() {
  local trouve=0 fichier
  while IFS= read -r fichier; do
    if ! head -1 "$fichier" | grep -q 'ANSIBLE_VAULT'; then
      echo "  $fichier n'est pas chiffre"
      trouve=1
    fi
  done < <(find ansible -name 'coffre*.yml' -not -name '*.example')
  return "$trouve"
}

lance "aucun coffre en clair" verifier_coffre

printf '\n'
[ "$echec" -eq 0 ] && printf '\033[32mTout est en ordre.\033[0m\n' || printf '\033[31mDes controles ont echoue.\033[0m\n'
exit "$echec"
