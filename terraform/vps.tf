# Le VPS n'est pas créé ici.
#
# Un VPS OVH se commande depuis l'espace client : le tunnel de commande passe
# par un paiement que l'API ne couvre pas de bout en bout. Terraform le lit
# donc comme une ressource existante et ne pilote que ce qui l'entoure — le
# DNS et le reverse DNS. Voir docs/adr/0001-terraform-et-ansible.md.

data "ovh_vps" "serveur" {
  service_name = var.vps_nom_service
}

locals {
  # `ips` mélange IPv4 et IPv6 ; on trie sur la présence de « : ».
  ips_v4_api = [for ip in data.ovh_vps.serveur.ips : ip if !strcontains(ip, ":")]
  ips_v6_api = [for ip in data.ovh_vps.serveur.ips : ip if strcontains(ip, ":")]

  # La valeur explicite l'emporte : elle permet de travailler avec un jeton API
  # dépourvu du droit de lecture sur /vps, et de figer l'IP si besoin.
  ipv4 = var.ipv4 != "" ? var.ipv4 : one(local.ips_v4_api)
  ipv6 = var.ipv6 != "" ? var.ipv6 : try(one(local.ips_v6_api), "")

  ipv6_actif = local.ipv6 != ""
}

# Reverse DNS. Sans lui, l'IP se présente sous le nom générique d'OVH.
resource "ovh_ip_reverse" "vps" {
  count = var.reverse_dns != "" ? 1 : 0

  ip         = "${local.ipv4}/32"
  ip_reverse = local.ipv4
  reverse    = var.reverse_dns
}
