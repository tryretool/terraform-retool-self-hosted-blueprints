###############################################################################
# The "prod" Retool instance. Identical in shape to myretool-dev.tf — only the
# prefix, domain and sizing differ. Adding a third instance means copying this
# file again, not touching shared.tf.
###############################################################################

locals {
  prod = {
    prefix      = "${local.prefix_global}-prod"
    domain_name = "myretool.acme.org"

    enable_https = false
  }
}

module "db-main-prod" {
  source  = "tryretool/self-hosted-blueprints/retool//modules/aws-database"
  version = "~> 0.4"

  prefix     = local.prod.prefix
  db_purpose = "main"

  instance_class        = "db.m5.large"
  allocated_storage     = 50
  max_allocated_storage = 500
  multi_az              = true

  vpc = module.vpc.outputs
  eks = module.eks.outputs
}

module "retool-services-prod" {
  source  = "tryretool/self-hosted-blueprints/retool//modules/aws-retool-services"
  version = "~> 0.4"

  prefix = local.prod.prefix
  region = local.region
  eks    = module.eks.outputs
  db     = module.db-main-prod.outputs

  license_key = "MY-LICENSE-KEY"

  depends_on = [module.eks]
}

module "retool-prod" {
  source  = "tryretool/self-hosted-blueprints/retool//modules/retool-helm"
  version = "~> 0.4"

  retool_helm_name          = "retool"
  retool_helm_chart_version = "6.11.15"

  db              = module.db-main-prod.outputs
  retool_services = module.retool-services-prod.outputs
  domain_name     = local.prod.domain_name
  https_enabled   = local.prod.enable_https

  retool_helm_extra_values = [yamlencode({
    image = {
      tag = "3.334.0-stable"
    }
    podDisruptionBudget = {
      maxUnavailable = 1
    }
  })]

  depends_on = [module.retool-services-prod]
}

module "user-ingress-prod" {
  source  = "tryretool/self-hosted-blueprints/retool//modules/aws-user-ingress"
  version = "~> 0.4"

  domain_name           = local.prod.domain_name
  enable_https_listener = local.prod.enable_https

  # Places the TargetGroupBinding in this instance's namespace, beside its
  # Retool Service.
  retool_services = module.retool-services-prod.outputs

  vpc = module.vpc.outputs
  eks = module.eks.outputs

  depends_on = [module.retool-services-prod, module.retool-prod]
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
