locals {
  prefix      = "blessed-02"
  project_id  = "my-gcp-project" # replace with your GCP project ID
  region      = "us-central1"
  base_domain = "retool.example.com" # replace with your domain
}

module "vpc" {
  source     = "../../modules/gcp/vpc"
  prefix     = local.prefix
  project_id = local.project_id
  region     = local.region
}

module "gke" {
  source     = "../../modules/gcp/gke"
  prefix     = local.prefix
  project_id = local.project_id
  region     = local.region

  network_name        = module.vpc.network_name
  subnet_name         = module.vpc.subnet_name
  pods_range_name     = module.vpc.pods_range_name
  services_range_name = module.vpc.services_range_name

  depends_on = [module.vpc]
}

module "db-main" {
  source     = "../../modules/gcp/database"
  prefix     = local.prefix
  project_id = local.project_id
  region     = local.region

  network_id = module.vpc.network_id
  db_purpose = "main"
  tier       = "db-g1-small"

  # Cloud SQL requires the VPC peering connection (google_service_networking_connection)
  # created by the vpc module's private_service_access submodule to exist before the
  # instance is created. This explicit dependency ensures correct ordering.
  depends_on = [module.vpc]
}

module "retool-services" {
  source     = "../../modules/gcp/retool-services"
  prefix     = local.prefix
  project_id = local.project_id
  region     = local.region

  gke = {
    cluster_name     = module.gke.cluster.name
    cluster_location = module.gke.cluster.location
    cluster_endpoint = module.gke.cluster.endpoint
  }

  db_credentials_secret_name = module.db-main.db_instance_master_user_secret_name

  # encryption_key_secret_name = null  # (default) auto-generates a random key
}

module "user-ingress" {
  source     = "../../modules/gcp/ingress"
  prefix     = local.prefix
  project_id = local.project_id
  region     = local.region

  base_domain = local.base_domain

  depends_on = [module.gke, module.retool-services]
}

module "retool" {
  source = "../../modules/common/retool-helm"

  retool_helm_name          = "retool"
  retool_helm_chart_version = "6.10.0"

  db = {
    address  = module.db-main.db_instance_address
    port     = module.db-main.db_instance_port
    name     = module.db-main.db_instance_database_name
    username = module.db-main.db_instance_username
  }

  retool_services = {
    encryption_key_secret_name = module.retool-services.k8s_encryption_key_secret_name
    jwt_secret_name            = module.retool-services.k8s_jwt_secret_name
    db_credentials_secret_name = module.retool-services.k8s_db_credentials_secret_name
    db_credentials_secret_key  = module.retool-services.k8s_db_credentials_secret_key
    db_credentials_secret_path = module.retool-services.sm_db_credentials_secret_name
    extra_env_vars_secret_name = module.retool-services.k8s_extra_env_vars_secret_name
    extra_env_vars_secret_path = module.retool-services.sm_extra_env_vars_secret_name
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
      # Disable the traditional Ingress — the Gateway HTTPRoute below handles routing.
      # Without this, the chart renders an Ingress with a null spec which fails validation.
      ingress = { enabled = false }
      httpRoute = {
        enabled   = true
        hostnames = [local.base_domain]
        parentRefs = [{
          name        = module.ingress.gateway_name
          namespace   = "default"
          sectionName = "https"
        }]
      }
      env = {
        BASE_DOMAIN = local.base_domain
      }
    }),
  ]

  depends_on = [module.gke, module.retool-services, module.ingress]
}

output "modules" {
  value = {
    vpc = module.vpc
    gke = module.gke
    db-main = module.db-main
    retool-services = module.retool-services
    user-ingress = module.user-ingress
    retool = module.retool
  }
}
