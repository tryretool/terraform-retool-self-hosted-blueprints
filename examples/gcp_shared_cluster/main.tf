###############################################################################
# Deploy Retool into a PRE-EXISTING (shared) GKE cluster.
#
# Unlike gcp_all_inclusive, this creates no VPC and no GKE cluster. It points
# gcp-gke at an existing cluster via existing_cluster, which installs only the
# cluster-wide operators Retool needs, and puts the Retool deployment itself in a
# single prefixed namespace, <prefix>-retool.
#
# The External Secrets Operator is a cluster singleton — its CRDs and webhooks
# have fixed cluster-scoped names, so exactly one copy can exist per cluster.
# Turn it off if your platform team already runs it. external-dns is NOT a
# singleton: it owns no CRDs, so each deployment runs its own, scoped to its own
# DNS zone and namespace.
#
# To add a SECOND Retool deployment to this cluster, do not instantiate gcp-gke
# again: deploy only retool-services, retool-helm and user-ingress with a
# different prefix.
#
# Requires Workload Identity enabled on the cluster, the Gateway API enabled
# (gateway_api_config), and private service access configured on the VPC for
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

# The provider blocks in provider.example.tf read the cluster endpoint directly
# from this data source, so it stays even though module.gke also resolves it.
data "google_container_cluster" "this" {
  name     = local.cluster_name
  location = local.cluster_location
  project  = local.project_id
}

# Adopts the existing cluster rather than creating one: no VPC, no node pools —
# only the cluster-wide operators. Instantiate this once per cluster, from one
# Terraform state.
module "gke" {
  source  = "tryretool/self-hosted-blueprints/retool//modules/gcp-gke"
  version = "~> 0.4"

  prefix     = local.prefix
  project_id = local.project_id
  region     = local.region

  existing_cluster = {
    name     = local.cluster_name
    location = local.cluster_location
  }

  # Turn off anything the cluster already runs.
  enable_external_secrets = true
  enable_reloader         = true

  # Set false if the External Secrets CRDs are already installed and managed out
  # of band.
  install_crds = true
}

module "db-main" {
  source  = "tryretool/self-hosted-blueprints/retool//modules/gcp-database"
  version = "~> 0.4"

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
  version = "~> 0.4"

  prefix     = local.prefix
  project_id = local.project_id
  region     = local.region
  gke        = module.gke.outputs
  db         = module.db-main.outputs

  # The namespace defaults to <prefix>-retool. Override to target a namespace the
  # platform team pre-created, and set create_namespace = false so this module
  # doesn't try to own it.
  # retool_namespace = "team-retool"
  # create_namespace = false

  # The SecretStore and ExternalSecrets must land after the operator's CRDs.
  depends_on = [module.gke]
}

module "user-ingress" {
  source  = "tryretool/self-hosted-blueprints/retool//modules/gcp-user-ingress"
  version = "~> 0.4"

  prefix      = local.prefix
  project_id  = local.project_id
  region      = local.region
  domain_name = local.domain_name

  retool_services = module.retool-services.outputs

  # Each deployment runs its own external-dns, scoped to the zone created here.
  # Set false to publish DNS records yourself.
  enable_external_dns = true

  depends_on = [module.retool-services]
}

module "retool" {
  source  = "tryretool/self-hosted-blueprints/retool//modules/retool-helm"
  version = "~> 0.4"

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
    gke             = module.gke
    db-main         = module.db-main
    retool-services = module.retool-services
    user-ingress    = module.user-ingress
    retool          = module.retool
  }
}
