###############################################################################
# The "dev" Retool instance. Everything here is per-instance: its own prefix,
# its own database, its own namespace, its own domain.
#
# This instance uses a dedicated Postgres instance. To share one Postgres
# instance across both Retool instances instead, see "Sharing a Postgres DB
# instance" in guides/shared-clusters.md.
###############################################################################

locals {
  dev = {
    prefix      = "${local.prefix_global}-dev"
    domain_name = "myretool-dev.acme.org"

    # user-ingress defaults to HTTP-only until you delegate DNS and flip this on
    # for ACM + HTTPS. Retool must use matching cookie settings: secure cookies
    # require HTTPS to the browser.
    enable_https = false
  }
}

module "db-main-dev" {
  source  = "tryretool/self-hosted-blueprints/retool//modules/aws-database"
  version = "~> 0.4"

  prefix     = local.dev.prefix
  db_purpose = "main"

  instance_class        = "db.t3.medium"
  allocated_storage     = 20
  max_allocated_storage = 200
  multi_az              = true

  vpc = module.vpc.outputs
  eks = module.eks.outputs
}

module "retool-services-dev" {
  source  = "tryretool/self-hosted-blueprints/retool//modules/aws-retool-services"
  version = "~> 0.4"

  prefix = local.dev.prefix
  region = local.region
  eks    = module.eks.outputs
  db     = module.db-main-dev.outputs

  license_key = "MY-LICENSE-KEY"

  depends_on = [module.eks]
}

module "retool-dev" {
  source  = "tryretool/self-hosted-blueprints/retool//modules/retool-helm"
  version = "~> 0.4"

  retool_helm_name          = "retool"
  retool_helm_chart_version = "6.11.15"

  db              = module.db-main-dev.outputs
  retool_services = module.retool-services-dev.outputs
  domain_name     = local.dev.domain_name
  https_enabled   = local.dev.enable_https

  retool_helm_extra_values = [yamlencode({
    image = {
      tag = "3.334.0-stable"
    }
    podDisruptionBudget = {
      maxUnavailable = 1
    }
  })]

  depends_on = [module.retool-services-dev]
}

module "user-ingress-dev" {
  source  = "tryretool/self-hosted-blueprints/retool//modules/aws-user-ingress"
  version = "~> 0.4"

  domain_name           = local.dev.domain_name
  enable_https_listener = local.dev.enable_https

  # Places the TargetGroupBinding in this instance's namespace, beside its
  # Retool Service.
  retool_services = module.retool-services-dev.outputs

  vpc = module.vpc.outputs
  eks = module.eks.outputs

  depends_on = [module.retool-services-dev, module.retool-dev]
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
