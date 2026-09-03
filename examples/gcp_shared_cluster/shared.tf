###############################################################################
# Two Retool instances — "dev" and "prod" — sharing one GKE cluster.
#
# Read guides/shared-clusters.md first. It explains which modules are shared and
# which are per-instance, and why; this example is just that guidance written
# out. The layout mirrors the guide:
#
#   shared.tf         the VPC and cluster, instantiated once
#   myretool-dev.tf   everything belonging to the dev instance
#   myretool-prod.tf  everything belonging to the prod instance
#
# Each Retool instance needs its own prefix, its own module names, and its own
# domain. Everything else follows from that.
###############################################################################

locals {
  # Shared by the resources below. Each instance derives its own prefix from
  # this, so names never collide.
  prefix_global = "acme-myretool"

  project_id = "my-gcp-project" # replace with your GCP project ID
  region     = "us-central1"
}

module "vpc" {
  source  = "tryretool/self-hosted-blueprints/retool//modules/gcp-vpc"
  version = "~> 0.4"

  prefix     = local.prefix_global
  project_id = local.project_id
  region     = local.region
}

# Installs the cluster-wide operators (External Secrets, reloader) as
# singletons. Exactly one instantiation per cluster — adding a third Retool
# instance later means another myretool-*.tf, not another copy of this.
module "gke" {
  source  = "tryretool/self-hosted-blueprints/retool//modules/gcp-gke"
  version = "~> 0.4"

  prefix     = local.prefix_global
  project_id = local.project_id
  region     = local.region
  vpc        = module.vpc.outputs

  depends_on = [module.vpc]
}

output "shared" {
  value = {
    vpc = module.vpc
    gke = module.gke
  }
}
