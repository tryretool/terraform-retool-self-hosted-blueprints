locals {
  prefix              = "retool-prod"
  location            = "eastus2"
  resource_group_name = "retool-prod"
  domain_name         = "retool.example.com" # replace with your domain

  # user-ingress defaults to HTTP-only until you delegate DNS and flip this on.
  # Retool must use matching cookie settings: secure cookies require HTTPS to the browser.
  enable_https = false
}

# Azure requires a resource group as the container for all resources.
resource "azurerm_resource_group" "main" {
  name     = "${local.prefix}-rg"
  location = local.location
}

module "vnet" {
  source  = "tryretool/self-hosted-blueprints/retool//modules/azure-vnet"
  version = "~> 0.0.1"

  prefix              = local.prefix
  resource_group_name = local.resource_group_name
  location            = local.location
}

module "aks" {
  source  = "tryretool/self-hosted-blueprints/retool//modules/azure-aks"
  version = "~> 0.0.1"

  prefix              = local.prefix
  resource_group_name = local.resource_group_name
  location            = local.location
  vnet                = module.vnet.outputs

  depends_on = [module.vnet]
}

module "db-main" {
  source  = "tryretool/self-hosted-blueprints/retool//modules/azure-database"
  version = "~> 0.0.1"

  prefix              = local.prefix
  resource_group_name = local.resource_group_name
  location            = local.location
  db_purpose          = "main"
  vnet                = module.vnet.outputs

  depends_on = [module.vnet]
}

module "retool-services" {
  source  = "tryretool/self-hosted-blueprints/retool//modules/azure-retool-services"
  version = "~> 0.0.1"

  prefix              = local.prefix
  resource_group_name = local.resource_group_name
  location            = local.location
  vnet                = module.vnet.outputs
  aks                 = module.aks.outputs

  db_credentials_secret_name = module.db-main.master_secret_name
}

module "user-ingress" {
  source  = "tryretool/self-hosted-blueprints/retool//modules/azure-user-ingress"
  version = "~> 0.0.1"

  prefix              = local.prefix
  resource_group_name = local.resource_group_name
  location            = local.location
  domain_name         = local.domain_name
  vnet                = module.vnet.outputs
  aks                 = module.aks.outputs
  enable_https        = local.enable_https

  depends_on = [module.aks, module.retool-services]
}

module "retool" {
  source  = "tryretool/self-hosted-blueprints/retool//modules/common/retool-helm"
  version = "~> 0.0.1"

  retool_helm_name          = "retool"
  retool_helm_chart_version = "6.10.0"

  db              = module.db-main.outputs
  retool_services = module.retool-services.outputs

  retool_helm_extra_values = [
    yamlencode({
      image = {
        tag = "3.334.0-stable"
      }
    }),
    yamlencode({
      ingress = {
        enabled          = true
        ingressClassName = "azure-application-gateway"
        annotations = {
          "appgw.ingress.kubernetes.io/health-probe-path" = "/api/checkHealth"
        }
        hosts = [{
          host = local.domain_name
          paths = [{
            path     = "/"
            pathType = "Prefix"
          }]
        }]
      }
      config = {
        useInsecureCookies = !local.enable_https
      }
      env = {
        BASE_DOMAIN = "${local.enable_https ? "https" : "http"}://${local.domain_name}"
      }
    }),
  ]

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
