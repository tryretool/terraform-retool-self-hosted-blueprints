locals {
  prefix      = "my-retool"
  project_id  = "my-gcp-project" # replace with your GCP project ID
  region      = "us-central1"
  domain_name = "retool.example.com" # replace with your domain
}

module "vpc" {
  source  = "tryretool/self-hosted-blueprints/retool//modules/gcp-vpc"
  version = "~> 0.3"

  prefix     = local.prefix
  project_id = local.project_id
  region     = local.region
}

module "gke" {
  source  = "tryretool/self-hosted-blueprints/retool//modules/gcp-gke"
  version = "~> 0.3"

  prefix     = local.prefix
  project_id = local.project_id
  region     = local.region
  vpc        = module.vpc.outputs

  depends_on = [module.vpc]
}

module "db-main" {
  source  = "tryretool/self-hosted-blueprints/retool//modules/gcp-database"
  version = "~> 0.3"

  prefix     = local.prefix
  project_id = local.project_id
  region     = local.region
  vpc        = module.vpc.outputs

  db_purpose = "main"
  tier       = "db-g1-small"
  # db-g1-small's default max_connections is too low for the full Retool stack.
  max_connections = 300

  # Cloud SQL requires the VPC peering connection (google_service_networking_connection)
  # created by the vpc module's private_service_access submodule to exist before the
  # instance is created. This explicit dependency ensures correct ordering.
  depends_on = [module.vpc]
}

module "retool-services" {
  source  = "tryretool/self-hosted-blueprints/retool//modules/gcp-retool-services"
  version = "~> 0.3"

  prefix     = local.prefix
  project_id = local.project_id
  region     = local.region
  gke        = module.gke.outputs
  db         = module.db-main.outputs

  license_key = "MY-LICENSE-KEY"
}

module "user-ingress" {
  source  = "tryretool/self-hosted-blueprints/retool//modules/gcp-user-ingress"
  version = "~> 0.3"

  prefix      = local.prefix
  project_id  = local.project_id
  region      = local.region
  domain_name = local.domain_name

  depends_on = [module.gke, module.retool-services]
}

module "retool" {
  source  = "tryretool/self-hosted-blueprints/retool//modules/retool-helm"
  version = "~> 0.3"

  retool_helm_name          = "retool"
  retool_helm_chart_version = "6.11.15"

  db              = module.db-main.outputs
  retool_services = module.retool-services.outputs
  user_ingress    = module.user-ingress.outputs
  domain_name     = local.domain_name

  retool_helm_extra_values = [yamlencode({
    image = {
      tag = "3.334.0-stable"
    }
  })]

  depends_on = [module.gke, module.retool-services, module.user-ingress]
}

output "modules" {
  value = {
    vpc             = module.vpc
    gke             = module.gke
    db-main         = module.db-main
    retool-services = module.retool-services
    user-ingress    = module.user-ingress
    retool          = module.retool
  }
}
