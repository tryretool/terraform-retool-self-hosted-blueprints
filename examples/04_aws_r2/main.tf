locals {
  prefix      = "blueprint-04"
  aws_profile = "retool"
  region      = "us-west-2"
  tags        = {}
  domain_name = "retool.mydomain.com" # Replace with your actual customer domain

  # user-ingress defaults to HTTP-only until you delegate DNS and flip this on for ACM + HTTPS.
  # Retool must use matching cookie settings: secure cookies require HTTPS to the browser.
  enable_user_ingress_https = false
}

module "vpc" {
  source = "../../modules/aws/vpc"
  prefix = local.prefix
}

module "eks" {
  source = "../../modules/aws/eks"
  prefix = local.prefix
  region = local.region
  vpc    = module.vpc.outputs
}

module "db-main" {
  source     = "../../modules/aws/database"
  prefix     = local.prefix
  db_purpose = "main"

  instance_class        = "db.t3.medium"
  allocated_storage     = 20
  max_allocated_storage = 200
  multi_az              = true

  vpc = module.vpc.outputs
  eks = module.eks.outputs
}

module "retool-services" {
  source = "../../modules/aws/retool-services"
  prefix = local.prefix
  region = local.region
  vpc    = module.vpc.outputs
  eks    = module.eks.outputs
  db     = module.db-main.outputs

  enable_agent_sandbox = true
  enable_rr_git_s3     = true
  license_key          = "SECRET"

  depends_on = [module.eks]
}

module "retool" {
  source                                   = "../../modules/common/retool-helm"
  retool_helm_name                         = "retool"
  retool_helm_chart_version                = "6.11.0"
  retool_helm_chart_use_unpublished_branch = "lfoster/agent-sandbox-support"
  db                                       = module.db-main.outputs
  retool_services                          = module.retool-services.outputs
  retool_helm_extra_values = [yamlencode({
    image = {
      repository = "753800337063.dkr.ecr.us-west-2.amazonaws.com/onprem"
      tag        = "dev-3.380.0-940f7d8"
    }
    config = {
      useInsecureCookies = !local.enable_user_ingress_https
    }
    ingress = {
      enabled = false
    }
    env = {
      BASE_DOMAIN = local.enable_user_ingress_https ? "https://${local.domain_name}" : "http://${local.domain_name}"
    }
    replicaCount = 2
    podDisruptionBudget = {
      maxUnavailable = 1
    }
    dbconnector = {
      enabled  = true
      replicas = 2
    }
    r2Agent = {
      enabled = true
    }
    telemetry = {
      enabled = true
      image = {
        tag = "3.334.0-stable"
      }
    }
    workflows = {
      enabled = true
      worker = {
        replicaCount = 2
      }
      backend = {
        replicaCount = 2
      }
    }
    codeExecutor = {
      enabled      = true
      replicaCount = 2
      image = {
        repository = "753800337063.dkr.ecr.us-west-2.amazonaws.com/code-executor-service"
        tag        = "dev-3.380.0-940f7d8"
      }
    }
    jsExecutor = {
      replicaCount = 2
      image = {
        repository = "753800337063.dkr.ecr.us-west-2.amazonaws.com/js-executor-service"
        tag        = "dev-3.380.0-940f7d8"
      }
    }
    agentSandbox = {
      enabled = true
      image = {
        repository = "753800337063.dkr.ecr.us-west-2.amazonaws.com/agent-executor-service"
        tag        = "dev-3.380.0-940f7d8"
      }
      postgres = {
        schema = "agent_executor"
      }
      externalSecret = {
        name = module.retool-services.outputs.agent_sandbox_secret_name
      }
      frontendWsProxyDomain = "${local.enable_user_ingress_https ? "https" : "http"}://agent-proxy.${local.domain_name}"
      proxy = {
        backendDomainSuffixes = local.domain_name
      }
    }
  })]

  depends_on = [module.retool-services]
}

module "user-ingress" {
  source = "../../modules/aws/user-ingress"

  domain_name                = local.domain_name
  enable_https_listener      = local.enable_user_ingress_https
  enable_agent_sandbox_proxy = true

  vpc = module.vpc.outputs
  eks = module.eks.outputs

  depends_on = [module.retool-services, module.retool]
}

output "modules" {
  value = {
    vpc             = module.vpc
    eks             = module.eks
    db-main         = module.db-main
    retool-services = module.retool-services
    user-ingress    = module.user-ingress
    retool          = module.retool
  }
}
