###############################################################################
# Deploy Retool into a PRE-EXISTING (shared) GKE cluster.
#
# Unlike gcp_all_inclusive, this does NOT create a VPC or a GKE cluster. It looks
# up an existing cluster and deploys only the Retool-specific pieces into
# dedicated, prefixed namespaces:
#   - <prefix>-retool           the Retool app + its Secrets + the Gateway
#   - <prefix>-retool-services  Retool's supporting operators (ESO, reloader,
#                               external-dns) — only the ones this deploy owns
#
# Cluster-wide singletons (ESO, external-dns) are assumed to already exist in the
# shared cluster and are turned OFF here. The SecretStore + ExternalSecrets are
# still created (the platform's ESO reconciles them); grant the platform ESO
# access to Retool's secrets — bind it to, or copy the IAM grants onto,
# module.retool-services.outputs.eso_gcp_service_account_email.
#
# Requires Workload Identity enabled on the cluster, the Gateway API CRDs present
# (GKE: gateway_api_config), and private service access configured on the VPC for
# Cloud SQL.
###############################################################################

locals {
  prefix      = "my-retool"
  project_id  = "my-gcp-project" # replace with your GCP project ID
  region      = "us-central1"
  domain_name = "retool.example.com" # replace with your domain

  # --- Existing shared infrastructure you must point at ---
  cluster_name     = "my-shared-gke" # existing GKE cluster name
  cluster_location = local.region    # region or zone the cluster runs in
  vpc_network_id   = "projects/my-gcp-project/global/networks/my-shared-vpc"
}

data "google_container_cluster" "this" {
  name     = local.cluster_name
  location = local.cluster_location
  project  = local.project_id
}

locals {
  gke = {
    name     = data.google_container_cluster.this.name
    location = data.google_container_cluster.this.location
    endpoint = data.google_container_cluster.this.endpoint
  }
}

module "db-main" {
  source  = "tryretool/self-hosted-blueprints/retool//modules/gcp-database"
  version = "~> 0.3"

  prefix     = local.prefix
  project_id = local.project_id
  region     = local.region

  vpc             = { network_id = local.vpc_network_id }
  db_purpose      = "main"
  tier            = "db-g1-small"
  max_connections = 300
}

module "retool-services" {
  source  = "tryretool/self-hosted-blueprints/retool//modules/gcp-retool-services"
  version = "~> 0.3"

  prefix     = local.prefix
  project_id = local.project_id
  region     = local.region
  gke        = local.gke
  db         = module.db-main.outputs

  # Namespaces default to <prefix>-retool / <prefix>-retool-services. Override and
  # set create_namespaces = false to target namespaces the platform pre-created.
  # retool_namespace   = "team-retool"
  # services_namespace = "team-retool"
  # create_namespaces  = false

  # The shared cluster already runs ESO; don't install a second copy.
  enable_external_secrets = false
  enable_reloader         = false
  install_crds            = false
}

module "user-ingress" {
  source  = "tryretool/self-hosted-blueprints/retool//modules/gcp-user-ingress"
  version = "~> 0.3"

  prefix      = local.prefix
  project_id  = local.project_id
  region      = local.region
  domain_name = local.domain_name

  retool_services = module.retool-services.outputs

  # The shared cluster already runs external-dns; point it at the created zone.
  enable_external_dns = false

  depends_on = [module.retool-services]
}

module "retool" {
  source  = "tryretool/self-hosted-blueprints/retool//modules/retool-helm"
  version = "~> 0.3"

  retool_helm_name          = "retool"
  retool_helm_chart_version = "6.11.1"

  db              = module.db-main.outputs
  retool_services = module.retool-services.outputs
  user_ingress    = module.user-ingress.outputs
  domain_name     = local.domain_name

  retool_helm_extra_values = [yamlencode({
    image = {
      tag = "3.334.0-stable"
    }
  })]

  depends_on = [module.retool-services, module.user-ingress]
}

output "modules" {
  value = {
    db-main         = module.db-main
    retool-services = module.retool-services
    user-ingress    = module.user-ingress
    retool          = module.retool
  }
}
