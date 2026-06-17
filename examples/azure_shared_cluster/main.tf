###############################################################################
# Deploy Retool into a PRE-EXISTING (shared) AKS cluster.
#
# Unlike azure_all_inclusive, this does NOT create a VNet or an AKS cluster. It
# looks up an existing cluster and deploys only the Retool-specific pieces into
# dedicated, prefixed namespaces:
#   - <prefix>-retool           the Retool app + its Secrets + the TLS Certificate
#   - <prefix>-retool-services  Retool's supporting operators this deploy owns
#
# This example assumes the shared cluster already runs ESO and cert-manager and
# already has an ingress controller, so it:
#   - disables the bundled ESO (enable_external_secrets = false) — federate the
#     platform ESO's service account to module.retool-services.outputs
#     .eso_identity_client_id, or grant its identity the Key Vault access.
#   - disables AGIC (enable_agic = false) and points Retool's Ingress at the
#     existing ingress class via ingress_class_name.
#   - consumes an existing cert-manager ClusterIssuer via cluster_issuer_name.
#
# Requires Workload Identity / OIDC enabled on the cluster.
###############################################################################

locals {
  subscription_id     = "00000000-0000-0000-0000-000000000000" # replace
  prefix              = "retool-prod"
  location            = "eastus2"
  resource_group_name = "retool-prod"
  domain_name         = "retool.example.com" # replace with your domain

  # --- Existing shared infrastructure you must point at ---
  cluster_name = "my-shared-aks" # existing AKS cluster name

  # Existing networking + Key Vault the platform team provisioned.
  vnet_id            = "/subscriptions/.../resourceGroups/.../providers/Microsoft.Network/virtualNetworks/my-vnet"
  postgres_subnet_id = "/subscriptions/.../resourceGroups/.../providers/Microsoft.Network/virtualNetworks/my-vnet/subnets/postgres"
  key_vault_id       = "/subscriptions/.../resourceGroups/.../providers/Microsoft.KeyVault/vaults/my-kv"
  key_vault_uri      = "https://my-kv.vault.azure.net/"

  # Ingress wiring for the existing controller.
  ingress_class_name  = "nginx"            # your cluster's ingress class
  cluster_issuer_name = "letsencrypt-prod" # an existing cert-manager ClusterIssuer
  enable_https        = true
}

data "azurerm_kubernetes_cluster" "this" {
  name                = local.cluster_name
  resource_group_name = local.resource_group_name
}

module "db-main" {
  source  = "tryretool/self-hosted-blueprints/retool//modules/azure-database"
  version = "~> 0.3"

  prefix              = local.prefix
  resource_group_name = local.resource_group_name
  location            = local.location
  db_purpose          = "main"

  vnet = {
    vnet_id            = local.vnet_id
    postgres_subnet_id = local.postgres_subnet_id
    key_vault_id       = local.key_vault_id
  }
}

module "retool-services" {
  source  = "tryretool/self-hosted-blueprints/retool//modules/azure-retool-services"
  version = "~> 0.3"

  prefix              = local.prefix
  resource_group_name = local.resource_group_name
  location            = local.location
  vnet                = { key_vault_id = local.key_vault_id, key_vault_uri = local.key_vault_uri }
  aks                 = { name = data.azurerm_kubernetes_cluster.this.name, oidc_issuer_url = data.azurerm_kubernetes_cluster.this.oidc_issuer_url }
  db                  = module.db-main.outputs

  # Override namespaces + set create_namespaces = false to target pre-created ones.
  # retool_namespace   = "team-retool"
  # services_namespace = "team-retool"
  # create_namespaces  = false

  # The shared cluster already runs ESO; don't install a second copy.
  enable_external_secrets = false
  enable_reloader         = false
  install_crds            = false
}

module "user-ingress" {
  source  = "tryretool/self-hosted-blueprints/retool//modules/azure-user-ingress"
  version = "~> 0.3"

  prefix              = local.prefix
  resource_group_name = local.resource_group_name
  location            = local.location
  domain_name         = local.domain_name
  aks                 = { oidc_issuer_url = data.azurerm_kubernetes_cluster.this.oidc_issuer_url }
  enable_https        = local.enable_https

  retool_services = module.retool-services.outputs

  # Bring-your-own ingress + cert-manager: don't create an Application Gateway or
  # install cert-manager; point Retool's Ingress at the existing class and issuer.
  enable_agic         = false
  enable_cert_manager = false
  ingress_class_name  = local.ingress_class_name
  cluster_issuer_name = local.cluster_issuer_name

  # appgw_subnet_id is unused when enable_agic = false, but the variable is
  # still required; any valid subnet id (or a placeholder) is fine.
  vnet = { appgw_subnet_id = local.postgres_subnet_id }
}

module "retool" {
  source  = "tryretool/self-hosted-blueprints/retool//modules/retool-helm"
  version = "~> 0.3"

  retool_helm_name          = "retool"
  retool_helm_chart_version = "6.11.1"

  db              = module.db-main.outputs
  retool_services = module.retool-services.outputs
  user_ingress    = module.user-ingress.outputs
  domain_name     = local.domain_name
  https_enabled   = local.enable_https

  retool_helm_extra_values = [yamlencode({
    image = {
      tag = "3.334.0-stable"
    }
  })]

  depends_on = [module.retool-services, module.user-ingress]
}

output "modules" {
  sensitive = true
  value = {
    db-main         = module.db-main
    retool-services = module.retool-services
    user-ingress    = module.user-ingress
    retool          = module.retool
  }
}
