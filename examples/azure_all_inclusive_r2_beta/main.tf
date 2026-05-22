locals {
  prefix              = "retool-prod"
  location            = "eastus2"
  resource_group_name = "retool-prod"
  domain_name         = "retool.example.com" # replace with your domain

  # user-ingress defaults to HTTP-only until you delegate DNS and flip this on.
  # Retool must use matching cookie settings: secure cookies require HTTPS to the browser.
  enable_https = false
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

  vnet = module.vnet.outputs
  aks  = module.aks.outputs
  db   = module.db-main.outputs

  enable_agent_sandbox = true
  enable_rr_blob       = true
  license_key          = "SECRET"
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

  enable_agent_sandbox_proxy = true

  depends_on = [module.aks, module.retool-services]
}

module "retool" {
  source  = "tryretool/self-hosted-blueprints/retool//modules/common/retool-helm"
  version = "~> 0.0.1"

  retool_helm_name                         = "retool"
  retool_helm_chart_version                = "6.11.0"
  retool_helm_chart_use_unpublished_branch = "r2"

  db              = module.db-main.outputs
  retool_services = module.retool-services.outputs

  # r2 enabled
  retool_helm_extra_values = [yamlencode({
    image = {
      tag = "3.391.0-edge"
    }
    ingress = {
      enabled          = true
      ingressClassName = "azure-application-gateway"
      annotations = {
        "cert-manager.io/issuer"                            = "letsencrypt-prod" # TODO link this to an user-ingress output
        "appgw.ingress.kubernetes.io/health-probe-path"     = "/api/checkHealth"
        "appgw.ingress.kubernetes.io/health-probe-timeout"  = "10"
        "appgw.ingress.kubernetes.io/health-probe-interval" = "15"
      }
      hosts = [for h in [local.domain_name, "*.${local.domain_name}"] : {
        host = h
        paths = [{
          path     = "/"
          pathType = "Prefix"
        }]
      }]
      tls = [{
        secretName = "${local.prefix}-tls"
        hosts = [
          local.domain_name,
          "*.${local.domain_name}",
        ]
      }]
    }
    config = {
      useInsecureCookies = !local.enable_https
    }
    env = {
      BASE_DOMAIN = "${local.enable_https ? "https" : "http"}://${local.domain_name}"
    }
    replicaCount = 1
    podDisruptionBudget = {
      maxUnavailable = 1
    }
    dbconnector = {
      enabled  = false
      replicas = 1
    }
    r2Agent = {
      enabled = true
    }
    workflows = {
      enabled = true
      worker = {
        replicaCount = 1
      }
      backend = {
        replicaCount = 1
      }
    }
    codeExecutor = {
      enabled      = true
      replicaCount = 1
    }
    jsExecutor = {
      enabled      = true
      replicaCount = 1
    }
    agentSandbox = {
      enabled = true
      postgres = {
        schema = "agent_executor"
      }
      externalSecret = {
        name = module.retool-services.outputs.agent_sandbox_secret_name
      }
      frontendWsProxyDomain = "${local.enable_https ? "https" : "http"}://agent-proxy.${local.domain_name}"
      proxy = {
        backendDomainSuffixes = local.domain_name
        ingress = {
          enabled          = true
          host             = "agent-proxy.${local.domain_name}"
          ingressClassName = "azure-application-gateway"
          annotations = {
            "cert-manager.io/cluster-issuer"                    = "letsencrypt-prod" # TODO link this to an user-ingress output
            "appgw.ingress.kubernetes.io/health-probe-path"     = "/health"
            "appgw.ingress.kubernetes.io/health-probe-timeout"  = "10"
            "appgw.ingress.kubernetes.io/health-probe-interval" = "15"
            "appgw.ingress.kubernetes.io/request-timeout"       = "40"
          }
          tls = [{
            secretName = "${local.prefix}-agent-proxy-tls"
            hosts      = ["agent-proxy.${local.domain_name}"]
          }]
        }
      }
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
