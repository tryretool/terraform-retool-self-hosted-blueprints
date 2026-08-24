###############################################################################
# Deploy Retool into a PRE-EXISTING (shared) AKS cluster.
#
# Unlike azure_all_inclusive, this creates no VNet and no AKS cluster. It points
# azure-aks at an existing cluster via existing_cluster, which installs only the
# cluster-wide operators Retool needs, and puts the Retool deployment itself in a
# single prefixed namespace, <prefix>-retool.
#
# The External Secrets Operator, cert-manager and reloader are cluster
# singletons — their CRDs and admission webhooks have fixed cluster-scoped names,
# so exactly one copy can exist per cluster. Turn off whichever your platform
# team already runs. AGIC is NOT a singleton: it binds 1:1 to an Application
# Gateway, so each deployment runs its own, scoped to its own IngressClass and
# namespace.
#
# This example brings its own ingress instead: it disables AGIC and points
# Retool's Ingress at an existing controller via ingress_class_name.
#
# To add a SECOND Retool deployment to this cluster, do not instantiate azure-aks
# again: deploy only retool-services, retool-helm and user-ingress with a
# different prefix.
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

# The provider blocks in provider.example.tf read the kube config directly from
# this data source, so it stays even though module.aks also resolves it.
data "azurerm_kubernetes_cluster" "this" {
  name                = local.cluster_name
  resource_group_name = local.resource_group_name
}

# Adopts the existing cluster rather than creating one: no VNet, no node pools —
# only the cluster-wide operators. Instantiate this once per cluster, from one
# Terraform state.
module "aks" {
  source  = "tryretool/self-hosted-blueprints/retool//modules/azure-aks"
  version = "~> 0.4"

  prefix              = local.prefix
  resource_group_name = local.resource_group_name
  location            = local.location

  existing_cluster = {
    name = local.cluster_name
  }

  # This cluster already runs all three, so install none of them. Flip any of
  # these on to have Retool's stack own it instead.
  enable_external_secrets = false
  enable_cert_manager     = false
  enable_reloader         = false
}

module "db-main" {
  source  = "tryretool/self-hosted-blueprints/retool//modules/azure-database"
  version = "~> 0.4"

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
  version = "~> 0.4"

  prefix              = local.prefix
  resource_group_name = local.resource_group_name
  location            = local.location
  vnet                = { key_vault_id = local.key_vault_id, key_vault_uri = local.key_vault_uri }
  aks                 = module.aks.outputs
  db                  = module.db-main.outputs

  # Override the namespace + set create_namespace = false to target a pre-created one.
  # retool_namespace   = "team-retool"
  # create_namespace = false

  # The shared cluster already runs ESO; don't install a second copy.
  # The platform runs the External Secrets Operator, so name the identity its
  # controller uses. This deployment's own <prefix>-eso identity is federated to
  # a service account in its namespace, which its SecretStore points at, so the
  # platform's controller reads only Retool's secrets.
  # eso_controller_role_arns is AWS-only; on Azure the equivalent wiring is the
  # federated credential this module already creates.

  depends_on = [module.aks]
}

module "user-ingress" {
  source  = "tryretool/self-hosted-blueprints/retool//modules/azure-user-ingress"
  version = "~> 0.4"

  prefix              = local.prefix
  resource_group_name = local.resource_group_name
  location            = local.location
  domain_name         = local.domain_name
  aks                 = module.aks.outputs
  enable_https        = local.enable_https

  retool_services = module.retool-services.outputs

  # Bring-your-own ingress + cert-manager: don't create an Application Gateway or
  # install cert-manager; point Retool's Ingress at the existing class and issuer.
  # This cluster already has an ingress controller, so don't create an
  # Application Gateway or a second AGIC; point Retool's Ingress at that class,
  # and at the cert-manager ClusterIssuer the platform already runs.
  enable_agic         = false
  ingress_class_name  = local.ingress_class_name
  cluster_issuer_name = local.cluster_issuer_name

  # appgw_subnet_id is unused when enable_agic = false, but the variable is
  # still required; any valid subnet id (or a placeholder) is fine.
  vnet = { appgw_subnet_id = local.postgres_subnet_id }
}

module "retool" {
  source  = "tryretool/self-hosted-blueprints/retool//modules/retool-helm"
  version = "~> 0.4"

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
    aks             = module.aks
    db-main         = module.db-main
    retool-services = module.retool-services
    user-ingress    = module.user-ingress
    retool          = module.retool
  }
}
