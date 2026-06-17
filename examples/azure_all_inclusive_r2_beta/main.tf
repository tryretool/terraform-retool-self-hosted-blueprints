locals {
  subscription_id     = "00000000-0000-0000-0000-000000000000" # replace with your Azure subscription ID
  prefix              = "retool-prod"
  location            = "eastus2"
  resource_group_name = "retool-prod"
  domain_name         = "retool.example.com" # replace with your domain

  # Note: with https required, user-ingress won't work for a new deployment
  # until you delegate DNS (i.e. install NS records) as the certificate cannot
  # validate until that point. Disable to allow insecure HTTP traffic if
  # desired.
  enable_https = true
}


module "vnet" {
  source  = "tryretool/self-hosted-blueprints/retool//modules/azure-vnet"
  version = "~> 0.3"

  prefix              = local.prefix
  resource_group_name = local.resource_group_name
  location            = local.location
}

module "aks" {
  source  = "tryretool/self-hosted-blueprints/retool//modules/azure-aks"
  version = "~> 0.3"

  prefix              = local.prefix
  resource_group_name = local.resource_group_name
  location            = local.location
  vnet                = module.vnet.outputs

  depends_on = [module.vnet]
}

module "db-main" {
  source  = "tryretool/self-hosted-blueprints/retool//modules/azure-database"
  version = "~> 0.3"

  prefix              = local.prefix
  resource_group_name = local.resource_group_name
  location            = local.location
  db_purpose          = "main"
  vnet                = module.vnet.outputs

  depends_on = [module.vnet]
}

module "retool-services" {
  source  = "tryretool/self-hosted-blueprints/retool//modules/azure-retool-services"
  version = "~> 0.3"

  prefix              = local.prefix
  resource_group_name = local.resource_group_name
  location            = local.location

  vnet = module.vnet.outputs
  aks  = module.aks.outputs
  db   = module.db-main.outputs

  enable_agent_sandbox = true
  enable_rr_blob       = true
  license_key          = "SECRET"
}

module "user-ingress" {
  source  = "tryretool/self-hosted-blueprints/retool//modules/azure-user-ingress"
  version = "~> 0.3"

  prefix              = local.prefix
  resource_group_name = local.resource_group_name
  location            = local.location
  domain_name         = local.domain_name
  vnet                = module.vnet.outputs
  aks                 = module.aks.outputs
  enable_https        = local.enable_https

  retool_services = module.retool-services.outputs

  depends_on = [module.aks, module.retool-services]
}

module "retool" {
  source  = "tryretool/self-hosted-blueprints/retool//modules/retool-helm"
  version = "~> 0.3"

  retool_helm_name                         = "retool"
  retool_helm_chart_version                = "6.11.15"

  db              = module.db-main.outputs
  retool_services = module.retool-services.outputs
  user_ingress    = module.user-ingress.outputs
  domain_name     = local.domain_name
  https_enabled   = local.enable_https

  retool_helm_extra_values = [yamlencode({
    image = {
      tag = "3.391.0-edge"
    }
    podDisruptionBudget = {
      maxUnavailable = 1
    }
  })]

  depends_on = [module.aks, module.retool-services, module.user-ingress]
}

output "modules" {
  sensitive = true
  value = {
    vnet            = module.vnet
    aks             = module.aks
    db-main         = module.db-main
    retool-services = module.retool-services
    user-ingress    = module.user-ingress
    retool          = module.retool
  }
}
