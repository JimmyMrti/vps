# Les identifiants ne sont jamais écrits ici. Ils viennent de l'environnement :
#
#   export OVH_ENDPOINT=ovh-eu
#   export OVH_APPLICATION_KEY=...
#   export OVH_APPLICATION_SECRET=...
#   export OVH_CONSUMER_KEY=...
#
# Ils se créent sur https://api.ovh.com/createToken/ en n'accordant que les
# droits strictement nécessaires (voir terraform/README.md).

provider "ovh" {
  endpoint = var.ovh_endpoint
}
