locals {
  prefix      = "my-retool"
  project_id  = "my-gcp-project" # replace with your GCP project ID
  region      = "us-central1"
  domain_name = "retool.example.com" # replace with your domain
}

module "vpc" {
  source  = "tryretool/self-hosted-blueprints/retool//modules/gcp-vpc"
  version = "~> 0.0.1"

  prefix     = local.prefix
  project_id = local.project_id
  region     = local.region
}

module "gke" {
  source  = "tryretool/self-hosted-blueprints/retool//modules/gcp-gke"
  version = "~> 0.0.1"

  prefix     = local.prefix
  project_id = local.project_id
  region     = local.region
  vpc        = module.vpc.outputs

  depends_on = [module.vpc]
}

module "db-main" {
  source  = "tryretool/self-hosted-blueprints/retool//modules/gcp-database"
  version = "~> 0.0.1"

  prefix     = local.prefix
  project_id = local.project_id
  region     = local.region
  vpc        = module.vpc.outputs
  db_purpose = "main"
  tier       = "db-g1-small"

  # Cloud SQL requires the VPC peering connection (google_service_networking_connection)
  # created by the vpc module's private_service_access submodule to exist before the
  # instance is created. This explicit dependency ensures correct ordering.
  depends_on = [module.vpc]
}

module "retool-services" {
  source  = "tryretool/self-hosted-blueprints/retool//modules/gcp-retool-services"
  version = "~> 0.0.1"

  prefix     = local.prefix
  project_id = local.project_id
  region     = local.region
  gke        = module.gke.outputs
  db         = module.db-main.outputs

  # encryption_key_secret_name = null  # (default) auto-generates a random key
}

module "user-ingress" {
  source  = "tryretool/self-hosted-blueprints/retool//modules/gcp-user-ingress"
  version = "~> 0.0.1"

  prefix      = local.prefix
  project_id  = local.project_id
  region      = local.region
  domain_name = local.domain_name

  depends_on = [module.gke, module.retool-services]
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
      # Disable the traditional Ingress — the Gateway HTTPRoute below handles routing.
      # Without this, the chart renders an Ingress with a null spec which fails validation.
      ingress = { enabled = false }
      httpRoute = {
        enabled   = true
        hostnames = [local.domain_name]
        parentRefs = [{
          name        = module.user-ingress.gateway_name
          namespace   = "default"
          sectionName = "https"
        }]
      }
      env = {
        BASE_DOMAIN = "https://${local.domain_name}"
      }
    }),
  ]

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
