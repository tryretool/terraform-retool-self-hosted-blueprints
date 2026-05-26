locals {
  prefix      = "retool-prod"
  aws_profile = "retool"
  region      = "us-west-2"
  tags        = {}
  domain_name = "retool.mydomain.com" # Replace with your actual customer domain

  # user-ingress defaults to HTTP-only until you delegate DNS and flip this on for ACM + HTTPS.
  # Retool must use matching cookie settings: secure cookies require HTTPS to the browser.
  enable_user_ingress_https = false
}

module "vpc" {
  source  = "tryretool/self-hosted-blueprints/retool//modules/aws-vpc"
  version = "~> 0.2"

  prefix = local.prefix
}

module "eks" {
  source  = "tryretool/self-hosted-blueprints/retool//modules/aws-eks"
  version = "~> 0.2"

  prefix = local.prefix
  region = local.region
  vpc    = module.vpc.outputs
}

module "db-main" {
  source  = "tryretool/self-hosted-blueprints/retool//modules/aws-database"
  version = "~> 0.2"

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
  source  = "tryretool/self-hosted-blueprints/retool//modules/aws-retool-services"
  version = "~> 0.2"

  prefix = local.prefix
  region = local.region
  vpc    = module.vpc.outputs
  eks    = module.eks.outputs
  db     = module.db-main.outputs

  enable_agent_sandbox = true
  enable_rr_s3         = true
  license_key          = "SECRET"

  depends_on = [module.eks]
}

module "retool" {
  source  = "tryretool/self-hosted-blueprints/retool//modules/common/retool-helm"
  version = "~> 0.2"

  retool_helm_name                         = "retool"
  retool_helm_chart_version                = "6.11.0"
  retool_helm_chart_use_unpublished_branch = "r2"
  db                                       = module.db-main.outputs
  retool_services                          = module.retool-services.outputs
  domain_name                              = local.domain_name
  https_enabled                            = local.enable_user_ingress_https

  retool_helm_extra_values = [yamlencode({
    image = {
      tag = "3.391.0-edge"
    }
    podDisruptionBudget = {
      maxUnavailable = 1
    }
    telemetry = {
      enabled = true
    }
  })]

  depends_on = [module.retool-services]
}

module "user-ingress" {
  source  = "tryretool/self-hosted-blueprints/retool//modules/aws-user-ingress"
  version = "~> 0.2"

  domain_name                = local.domain_name
  enable_https_listener      = local.enable_user_ingress_https
  enable_agent_sandbox_proxy = true

  vpc = module.vpc.outputs
  eks = module.eks.outputs

  depends_on = [module.retool-services, module.retool]
}

output "modules" {
  sensitive = true # just to quiet the apply output
  value = {
    vpc             = module.vpc
    eks             = module.eks
    db-main         = module.db-main
    retool-services = module.retool-services
    user-ingress    = module.user-ingress
    retool          = module.retool
  }
}
