###############################################################################
# The "dev" Retool instance. Everything here is per-instance: its own prefix,
# its own database, its own namespace, its own domain.
#
# This instance uses a dedicated Cloud SQL instance. To share one Postgres
# instance across both Retool instances instead, see "Sharing a Postgres DB
# instance" in guides/shared-clusters.md.
###############################################################################

locals {
  dev = {
    prefix      = "${local.prefix_global}-dev"
    domain_name = "myretool-dev.acme.org"
  }
}

module "db-main-dev" {
  source  = "tryretool/self-hosted-blueprints/retool//modules/gcp-database"
  version = "~> 0.4"

  prefix     = local.dev.prefix
  project_id = local.project_id
  region     = local.region
  vpc        = module.vpc.outputs

  db_purpose = "main"
  tier       = "db-g1-small"
  # db-g1-small's default max_connections is too low for the full Retool stack.
  max_connections = 300

  # Cloud SQL requires the VPC peering connection created by the vpc module's
  # private_service_access submodule to exist first.
  depends_on = [module.vpc]
}

module "retool-services-dev" {
  source  = "tryretool/self-hosted-blueprints/retool//modules/gcp-retool-services"
  version = "~> 0.4"

  prefix     = local.dev.prefix
  project_id = local.project_id
  region     = local.region
  gke        = module.gke.outputs
  db         = module.db-main-dev.outputs

  license_key = "MY-LICENSE-KEY"

  depends_on = [module.gke]
}

module "user-ingress-dev" {
  source  = "tryretool/self-hosted-blueprints/retool//modules/gcp-user-ingress"
  version = "~> 0.4"

  prefix      = local.dev.prefix
  project_id  = local.project_id
  region      = local.region
  domain_name = local.dev.domain_name

  retool_services = module.retool-services-dev.outputs

  depends_on = [module.gke, module.retool-services-dev]
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

  retool_helm_extra_values = [yamlencode({
    image = {
      tag = "3.334.0-stable"
    }
  })]

  depends_on = [module.gke, module.retool-services-dev, module.user-ingress-dev]
}

output "dev" {
  value = {
    db-main         = module.db-main-dev
    retool-services = module.retool-services-dev
    user-ingress    = module.user-ingress-dev
    retool          = module.retool-dev
  }
}
