###############################################################################
# The "prod" Retool instance. Identical in shape to myretool-dev.tf — only the
# prefix and domain differ. Adding a third instance means copying this file
# again, not touching shared.tf.
###############################################################################

locals {
  prod = {
    prefix      = "${local.prefix_global}-prod"
    domain_name = "myretool.acme.org"

    enable_https = true
  }
}

module "db-main-prod" {
  source  = "tryretool/self-hosted-blueprints/retool//modules/azure-database"
  version = "~> 0.4"

  prefix              = local.prod.prefix
  resource_group_name = local.resource_group_name
  location            = local.location
  db_purpose          = "main"
  vnet                = module.vnet.outputs

  depends_on = [module.vnet]
}

module "retool-services-prod" {
  source  = "tryretool/self-hosted-blueprints/retool//modules/azure-retool-services"
  version = "~> 0.4"

  prefix              = local.prod.prefix
  resource_group_name = local.resource_group_name
  location            = local.location
  vnet                = module.vnet.outputs
  aks                 = module.aks.outputs
  db                  = module.db-main-prod.outputs

  license_key = "MY-LICENSE-KEY"

  depends_on = [module.aks]
}

module "user-ingress-prod" {
  source  = "tryretool/self-hosted-blueprints/retool//modules/azure-user-ingress"
  version = "~> 0.4"

  prefix              = local.prod.prefix
  resource_group_name = local.resource_group_name
  location            = local.location
  domain_name         = local.prod.domain_name
  vnet                = module.vnet.outputs
  aks                 = module.aks.outputs
  enable_https        = local.prod.enable_https

  retool_services = module.retool-services-prod.outputs

  depends_on = [module.aks, module.retool-services-prod]
}

module "retool-prod" {
  source  = "tryretool/self-hosted-blueprints/retool//modules/retool-helm"
  version = "~> 0.4"

  retool_helm_name          = "retool"
  retool_helm_chart_version = "6.11.15"

  db              = module.db-main-prod.outputs
  retool_services = module.retool-services-prod.outputs
  user_ingress    = module.user-ingress-prod.outputs
  domain_name     = local.prod.domain_name
  https_enabled   = local.prod.enable_https

  retool_helm_extra_values = [yamlencode({
    image = {
      tag = "3.334.0-stable"
    }
  })]

  depends_on = [module.aks, module.retool-services-prod, module.user-ingress-prod]
}

output "prod" {
  sensitive = true
  value = {
    db-main         = module.db-main-prod
    retool-services = module.retool-services-prod
    user-ingress    = module.user-ingress-prod
    retool          = module.retool-prod
  }
}
