###############################################################################
# The "dev" Retool instance. Everything here is per-instance: its own prefix,
# its own database, its own namespace, its own domain, and its own Application
# Gateway + AGIC.
#
# This instance uses a dedicated Postgres instance. To share one Postgres
# instance across both Retool instances instead, see "Sharing a Postgres DB
# instance" in guides/shared-clusters.md.
###############################################################################

locals {
  dev = {
    prefix      = "${local.prefix_global}-dev"
    domain_name = "myretool-dev.acme.org"

    # With https on, user-ingress won't serve traffic until you delegate DNS
    # (i.e. install NS records) — the certificate cannot validate before that.
    enable_https = true
  }
}

module "db-main-dev" {
  source  = "tryretool/self-hosted-blueprints/retool//modules/azure-database"
  version = "~> 0.4"

  prefix              = local.dev.prefix
  resource_group_name = local.resource_group_name
  location            = local.location
  db_purpose          = "main"
  vnet                = module.vnet.outputs

  depends_on = [module.vnet]
}

module "retool-services-dev" {
  source  = "tryretool/self-hosted-blueprints/retool//modules/azure-retool-services"
  version = "~> 0.4"

  prefix              = local.dev.prefix
  resource_group_name = local.resource_group_name
  location            = local.location
  vnet                = module.vnet.outputs
  aks                 = module.aks.outputs
  db                  = module.db-main-dev.outputs

  license_key = "MY-LICENSE-KEY"

  depends_on = [module.aks]
}

module "user-ingress-dev" {
  source  = "tryretool/self-hosted-blueprints/retool//modules/azure-user-ingress"
  version = "~> 0.4"

  prefix              = local.dev.prefix
  resource_group_name = local.resource_group_name
  location            = local.location
  domain_name         = local.dev.domain_name
  vnet                = module.vnet.outputs
  aks                 = module.aks.outputs
  enable_https        = local.dev.enable_https

  retool_services = module.retool-services-dev.outputs

  depends_on = [module.aks, module.retool-services-dev]
}

module "retool-dev" {
  source  = "tryretool/self-hosted-blueprints/retool//modules/retool-helm"
  version = "~> 0.4"

  retool_helm_name          = "retool"
  retool_helm_chart_version = "6.11.15"

  db              = module.db-main-dev.outputs
  retool_services = module.retool-services-dev.outputs
  user_ingress    = module.user-ingress-dev.outputs
  domain_name     = local.dev.domain_name
  https_enabled   = local.dev.enable_https

  retool_helm_extra_values = [yamlencode({
    image = {
      tag = "3.334.0-stable"
    }
  })]

  depends_on = [module.aks, module.retool-services-dev, module.user-ingress-dev]
}

output "dev" {
  sensitive = true
  value = {
    db-main         = module.db-main-dev
    retool-services = module.retool-services-dev
    user-ingress    = module.user-ingress-dev
    retool          = module.retool-dev
  }
}
