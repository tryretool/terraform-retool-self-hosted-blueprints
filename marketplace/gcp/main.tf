# Marketplace mpdev looks only in main.tf for these blocks so it can inject the
# goog-partner-solution consumption-tracking label into default_labels.
# Do not move them to another .tf file.
provider "google" {
  project = var.project_id
  region  = var.region
}

provider "google-beta" {
  project = var.project_id
  region  = var.region
}

locals {
  helm_chart_repository = (
    startswith(var.helm_chart_repo, "oci://") ||
    startswith(var.helm_chart_repo, "https://") ||
    startswith(var.helm_chart_repo, "http://") ||
    startswith(var.helm_chart_repo, "git+")
  ) ? var.helm_chart_repo : "oci://${var.helm_chart_repo}"

  # Marketplace requires goog_cm_deployment_name and uses it to name the
  # customer's deployment. SA account_id is max 30 chars; modules append
  # suffixes like "-external-dns" (13), so keep the prefix to 16.
  sanitized_deployment = lower(replace(var.goog_cm_deployment_name, "/[^a-z0-9]/", ""))
  prefix = (
    var.prefix != "" ? var.prefix : (
      local.sanitized_deployment != "" ? substr(local.sanitized_deployment, 0, 16) : "rtmp"
    )
  )
  helm_release_name = (
    var.helm_release_name != "" ? var.helm_release_name : (
      var.goog_cm_deployment_name != "" ? lower(var.goog_cm_deployment_name) : "retool"
    )
  )
}

module "vpc" {
  source = "../../modules/gcp-vpc"

  prefix     = local.prefix
  project_id = var.project_id
  region     = var.region
}

module "gke" {
  source = "../../modules/gcp-gke"

  prefix     = local.prefix
  project_id = var.project_id
  region     = var.region
  vpc        = module.vpc.outputs

  depends_on = [module.vpc]
}

module "db-main" {
  source = "../../modules/gcp-database"

  prefix          = local.prefix
  project_id      = var.project_id
  region          = var.region
  vpc             = module.vpc.outputs
  db_purpose      = "main"
  tier            = "db-g1-small"
  max_connections = 300

  depends_on = [module.vpc]
}

module "retool-services" {
  source = "../../modules/gcp-retool-services"

  prefix      = local.prefix
  project_id  = var.project_id
  region      = var.region
  gke         = module.gke.outputs
  db          = module.db-main.outputs
  license_key = var.license_key != "" ? var.license_key : null

  external_secrets_chart = {
    repository       = var.third_party_charts_repo
    version          = "2.8.0"
    image_repository = var.external_secrets_image_repo
    image_tag        = var.external_secrets_image_tag
  }

  reloader_chart = {
    repository       = var.third_party_charts_repo
    version          = "2.2.14"
    image_repository = var.reloader_image_repo
    image_tag        = var.reloader_image_tag
  }
}

module "user-ingress" {
  source = "../../modules/gcp-user-ingress"

  prefix      = local.prefix
  project_id  = var.project_id
  region      = var.region
  domain_name = var.domain_name

  external_dns_chart = {
    repository       = var.third_party_charts_repo
    version          = "1.21.1"
    image_repository = var.external_dns_image_repo
    image_tag        = var.external_dns_image_tag
  }

  depends_on = [module.gke, module.retool-services]
}
