output "ipv4" {
  description = "IPv4 publique du VPS, telle qu'utilisée dans les enregistrements DNS."
  value       = local.ipv4
}

output "ipv6" {
  description = "IPv6 publique du VPS, si elle existe."
  value       = local.ipv6 != "" ? local.ipv6 : null
}

output "domaines_servis" {
  description = "Tous les noms qui pointent vers le VPS. Doit correspondre aux fichiers edge/sites/*.caddy."
  value = sort(concat(
    keys(var.domaines),
    [for nom, conf in var.domaines : "www.${nom}" if conf.www]
  ))
}

output "inventaire_ansible" {
  description = "Bloc à reporter dans ansible/inventaire/production.yml."
  value       = <<-EOT
    ansible_host: ${local.ipv4}
  EOT
}
