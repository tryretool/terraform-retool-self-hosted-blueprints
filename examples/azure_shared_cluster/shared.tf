###############################################################################
# Two Retool instances — "dev" and "prod" — sharing one AKS cluster.
#
# Read guides/shared-clusters.md first. It explains which modules are shared and
# which are per-instance, and why; this example is just that guidance written
# out. The layout mirrors the guide:
#
#   shared.tf         the VNet and cluster, instantiated once
#   myretool-dev.tf   everything belonging to the dev instance
#   myretool-prod.tf  everything belonging to the prod instance
#
# Each Retool instance needs its own prefix, its own module names, and its own
# domain. Everything else follows from that.
###############################################################################

locals {
  # Shared by the resources below. Each instance derives its own prefix from
  # this, so names never collide.
  prefix_global = "acme-myretool"

  subscription_id     = "00000000-0000-0000-0000-000000000000" # replace with your Azure subscription ID
  location            = "eastus2"
  resource_group_name = "acme-myretool"
}

module "vnet" {
  source  = "tryretool/self-hosted-blueprints/retool//modules/azure-vnet"
  version = "~> 0.4"

  prefix              = local.prefix_global
  resource_group_name = local.resource_group_name
  location            = local.location
}

# Installs the cluster-wide operators (External Secrets, cert-manager, reloader)
# as singletons. Exactly one instantiation per cluster — adding a third Retool
# instance later means another myretool-*.tf, not another copy of this.
#
# AGIC is deliberately not here: it binds 1:1 to an Application Gateway, so each
# instance runs its own from its own user-ingress module.
module "aks" {
  source  = "tryretool/self-hosted-blueprints/retool//modules/azure-aks"
  version = "~> 0.4"

  prefix              = local.prefix_global
  resource_group_name = local.resource_group_name
  location            = local.location
  vnet                = module.vnet.outputs

  depends_on = [module.vnet]
}

output "shared" {
  sensitive = true # just to quiet the apply output
  value = {
    vnet = module.vnet
    aks  = module.aks
  }
}
