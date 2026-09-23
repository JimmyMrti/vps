# Raccourcis. Tout passe par ansible-playbook ou terraform : rien ici n'est
# indispensable, c'est du confort.

ANSIBLE := cd ansible &&

.DEFAULT_GOAL := aide

.PHONY: aide
aide:  ## Affiche cette aide
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

.PHONY: verifier
verifier:  ## Contrôles du dépôt, sans toucher au serveur
	./scripts/verifier.sh

.PHONY: dependances
dependances:  ## Installe les collections Ansible
	$(ANSIBLE) ansible-galaxy install -r requirements.yml

.PHONY: apercu
apercu:  ## Ce que le playbook changerait, sans rien changer
	$(ANSIBLE) ansible-playbook site.yml --check --diff

.PHONY: appliquer
appliquer:  ## Joue le playbook complet
	$(ANSIBLE) ansible-playbook site.yml

.PHONY: durcir
durcir:  ## Le socle seul, sans toucher aux services
	$(ANSIBLE) ansible-playbook durcissement.yml

.PHONY: etat
etat:  ## Constate l'état du serveur
	$(ANSIBLE) ansible-playbook verification.yml

.PHONY: coffre
coffre:  ## Ouvre le coffre des secrets
	$(ANSIBLE) ansible-vault edit inventaire/group_vars/all/coffre.yml
