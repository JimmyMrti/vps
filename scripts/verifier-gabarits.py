#!/usr/bin/env python3
"""Vérifie que chaque gabarit Jinja du dépôt est syntaxiquement valide.

Un gabarit cassé ne se découvre normalement qu'au déploiement, c'est-à-dire
au moment où l'on a le moins envie de le découvrir.

Ce contrôle porte sur la syntaxe seule : il ne cherche pas à rendre les
gabarits, ce qui demanderait toutes les variables d'Ansible.
"""

import pathlib
import sys

import jinja2

RACINE = pathlib.Path(__file__).resolve().parent.parent
environnement = jinja2.Environment(undefined=jinja2.ChainableUndefined)

echecs = []
gabarits = sorted(RACINE.glob("ansible/roles/*/templates/*.j2"))

for gabarit in gabarits:
    try:
        environnement.parse(gabarit.read_text(encoding="utf-8"))
    except jinja2.TemplateSyntaxError as erreur:
        echecs.append(f"  {gabarit.relative_to(RACINE)}:{erreur.lineno} — {erreur.message}")

print(f"  {len(gabarits)} gabarits examinés")

if echecs:
    print("\n".join(echecs), file=sys.stderr)
    sys.exit(1)
