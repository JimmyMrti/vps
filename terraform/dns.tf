# ===========================================================================
# DNS.
#
# Un domaine par service, chacun pointant vers le même VPS.
#
# ATTENTION AU PREMIER PASSAGE : les enregistrements de
# preventioncambriolage.fr existent déjà et servent le site en production.
# Ils doivent être IMPORTÉS avant tout apply, sans quoi Terraform en crée
# d'autres à côté et la zone se retrouve avec des doublons — donc un site qui
# répond une fois sur deux. Procédure dans README.md.
# ===========================================================================

locals {
  # Les domaines qui veulent aussi un nom en www.
  domaines_www = {
    for nom, conf in var.domaines : nom => conf if conf.www
  }

  # Les domaines qui déclarent n'envoyer aucun courrier.
  domaines_sans_courriel = {
    for nom, conf in var.domaines : nom => conf if conf.sans_courriel
  }

  courriel = var.courriel_technique != "" ? var.courriel_technique : "postmaster@${keys(var.domaines)[0]}"
}

# --- Apex -------------------------------------------------------------------

resource "ovh_domain_zone_record" "apex_a" {
  for_each = var.domaines

  zone      = each.key
  subdomain = ""
  fieldtype = "A"
  ttl       = var.ttl
  target    = local.ipv4
}

resource "ovh_domain_zone_record" "apex_aaaa" {
  for_each = local.ipv6_actif ? var.domaines : {}

  zone      = each.key
  subdomain = ""
  fieldtype = "AAAA"
  ttl       = var.ttl
  target    = local.ipv6
}

# --- www --------------------------------------------------------------------

resource "ovh_domain_zone_record" "www_a" {
  for_each = local.domaines_www

  zone      = each.key
  subdomain = "www"
  fieldtype = "A"
  ttl       = var.ttl
  target    = local.ipv4
}

resource "ovh_domain_zone_record" "www_aaaa" {
  for_each = local.ipv6_actif ? local.domaines_www : {}

  zone      = each.key
  subdomain = "www"
  fieldtype = "AAAA"
  ttl       = var.ttl
  target    = local.ipv6
}

# --- Courrier : dire explicitement que ces domaines n'en envoient pas -------
#
# Deux lignes qui suppriment l'usurpation du domaine dans les campagnes
# d'hameçonnage — ce qui, pour un site de prévention des cambriolages, n'est
# pas un détail : un courriel « de la part de » preventioncambriolage.fr a
# exactement le profil d'appât recherché.
#
# Le jour où un service doit émettre du courrier, passer `sans_courriel` à
# false pour ce domaine ET mettre en place SPF et DKIM AVANT. Sinon les
# messages partiront pour être rejetés.

resource "ovh_domain_zone_record" "spf" {
  for_each = local.domaines_sans_courriel

  zone      = each.key
  subdomain = ""
  fieldtype = "TXT"
  ttl       = var.ttl
  target    = "\"v=spf1 -all\""
}

resource "ovh_domain_zone_record" "dmarc" {
  for_each = local.domaines_sans_courriel

  zone      = each.key
  subdomain = "_dmarc"
  fieldtype = "TXT"
  ttl       = var.ttl
  target    = "\"v=DMARC1; p=reject; rua=mailto:${local.courriel}\""
}

# DKIM vide : aucune clé ne signe pour ce domaine.
resource "ovh_domain_zone_record" "dkim_neant" {
  for_each = local.domaines_sans_courriel

  zone      = each.key
  subdomain = "*._domainkey"
  fieldtype = "TXT"
  ttl       = var.ttl
  target    = "\"v=DKIM1; p=\""
}

# --- CAA : restreindre qui peut émettre un certificat -----------------------
#
# Sans CAA, n'importe quelle autorité de certification peut émettre pour le
# domaine. Avec, seule celle qu'on utilise le peut.

resource "ovh_domain_zone_record" "caa_issue" {
  for_each = var.domaines

  zone      = each.key
  subdomain = ""
  fieldtype = "CAA"
  ttl       = var.ttl
  target    = "0 issue \"letsencrypt.org\""
}

resource "ovh_domain_zone_record" "caa_iodef" {
  for_each = var.domaines

  zone      = each.key
  subdomain = ""
  fieldtype = "CAA"
  ttl       = var.ttl
  target    = "0 iodef \"mailto:${local.courriel}\""
}
