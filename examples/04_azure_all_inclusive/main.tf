locals {
  prefix              = "blessed-04"
  location            = "eastus2"
  resource_group_name = "retool-blessed-04"
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
  source = "../../modules/azure/vnet"

  prefix              = local.prefix
  resource_group_name = local.resource_group_name
  location            = local.location
}

module "aks" {
  source = "../../modules/azure/aks"

  prefix              = local.prefix
  resource_group_name = local.resource_group_name
  location            = local.location
  aks_subnet_id       = module.vnet.aks_subnet_id

  depends_on = [module.vnet]
}

module "db-main" {
  source = "../../modules/azure/database"

  prefix              = local.prefix
  resource_group_name = local.resource_group_name
  location            = local.location
  db_purpose          = "main"
  vnet_id             = module.vnet.vnet_id
  postgres_subnet_id  = module.vnet.postgres_subnet_id
  key_vault_id        = module.vnet.key_vault_id

  depends_on = [module.vnet]
}

module "retool-services" {
  source = "../../modules/azure/retool-services"

  prefix              = local.prefix
  resource_group_name = local.resource_group_name
  location            = local.location

  aks = {
    cluster_name    = module.aks.cluster.name
    oidc_issuer_url = module.aks.cluster.oidc_issuer_url
  }

  key_vault_id  = module.vnet.key_vault_id
  key_vault_uri = module.vnet.key_vault_uri

  db_credentials_secret_name = module.db-main.db_password_kv_secret_name
}

module "user-ingress" {
  source = "../../modules/azure/user-ingress"

  prefix              = local.prefix
  resource_group_name = local.resource_group_name
  location            = local.location
  domain_name         = local.domain_name
  appgw_subnet_id     = module.vnet.appgw_subnet_id
  enable_https        = local.enable_https

  aks = {
    cluster_name    = module.aks.cluster.name
    oidc_issuer_url = module.aks.cluster.oidc_issuer_url
  }

  depends_on = [module.aks, module.retool-services]
}

module "retool" {
  source = "../../modules/common/retool-helm"

  retool_helm_name          = "retool"
  retool_helm_chart_version = "6.10.0"

  db = {
    address  = module.db-main.db_instance_fqdn
    port     = module.db-main.db_instance_port
    name     = module.db-main.db_instance_name
    username = module.db-main.db_instance_username
  }

  retool_services = {
    encryption_key_secret_name = module.retool-services.k8s_encryption_key_secret_name
    jwt_secret_name            = module.retool-services.k8s_jwt_secret_name
    db_credentials_secret_name = module.retool-services.k8s_db_credentials_secret_name
    db_credentials_secret_key  = module.retool-services.k8s_db_credentials_secret_key
    db_credentials_secret_path = module.retool-services.kv_db_credentials_secret_name
    extra_env_vars_secret_name = module.retool-services.k8s_extra_env_vars_secret_name
    extra_env_vars_secret_path = module.retool-services.kv_extra_env_vars_secret_name
    secret_store_name          = module.retool-services.secret_store_name
    backend_type               = module.retool-services.backend_type
  }

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
    vpc             = module.vpc
    eks             = module.eks
    db-main         = module.db-main
    retool-services = module.retool-services
    user-ingress    = module.user-ingress
    retool          = module.retool
  }
}
