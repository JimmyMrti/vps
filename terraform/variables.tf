variable "ovh_endpoint" {
  description = "Point d'entrée de l'API OVH (ovh-eu pour un compte européen)."
  type        = string
  default     = "ovh-eu"
}

variable "vps_nom_service" {
  description = <<-EOT
    Nom de service du VPS chez OVH, de la forme « vpsXXXXXX.ovh.net ».
    Visible dans l'espace client, onglet VPS. Sert à lire l'IP et à poser
    le reverse DNS ; le VPS lui-même n'est pas créé par Terraform.
  EOT
  type        = string
}

variable "ipv4" {
  description = <<-EOT
    IPv4 publique du VPS. Laisser vide pour la lire depuis l'API OVH.
    À renseigner uniquement si le jeton API n'a pas le droit de lecture VPS.
  EOT
  type        = string
  default     = ""
}

variable "ipv6" {
  description = "IPv6 publique du VPS. Vide = lue depuis l'API, ou pas d'AAAA."
  type        = string
  default     = ""
}

variable "domaines" {
  description = <<-EOT
    Les domaines servis par ce VPS, un par service.

    Jim a tranché : aucun sous-domaine partagé. Chaque service a son propre
    domaine, ce qui isole les politiques de sécurité de contenu, évite qu'un
    nom de service apparaisse dans les journaux publics de certificats du
    domaine de la marque, et permet de céder ou d'arrêter un service sans
    toucher aux autres.

    Chaque entrée est une zone DNS hébergée chez OVH. `www` crée en plus un
    enregistrement pour le nom avec www.
  EOT
  type = map(object({
    commentaire = string
    www         = optional(bool, false)
    # Le domaine n'envoie pas de courrier : SPF fermé, DMARC en rejet.
    # À passer à false le jour où un service émet réellement des messages,
    # APRÈS avoir mis en place SPF et DKIM pour l'expéditeur retenu.
    sans_courriel = optional(bool, true)
  }))

  default = {
    "preventioncambriolage.fr" = {
      commentaire = "Site statique déjà en production"
      www         = false
    }
  }
}

variable "ttl" {
  description = "TTL des enregistrements, en secondes. 300 pendant une migration, 3600 en régime établi."
  type        = number
  default     = 3600
}

variable "reverse_dns" {
  description = <<-EOT
    Nom à publier en reverse DNS pour l'IPv4 du VPS. Vide = inchangé.
    Doit être un nom qui résout vers cette IP, sans quoi certains filtres le
    considèrent comme incohérent.
  EOT
  type        = string
  default     = ""
}

variable "courriel_technique" {
  description = "Adresse recevant les rapports DMARC et les signalements CAA."
  type        = string
  default     = ""
}
