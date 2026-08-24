# Adopting a pre-existing cluster.
#
# When var.existing_cluster is set this module creates no cluster, node pool or
# node service account, and instead resolves the same attributes from the live
# cluster so the operators below and this module's outputs behave identically in
# both modes.
#
# Everything else in this module reads local.cluster rather than
# google_container_cluster.gke directly, so neither branch is ever indexed when
# it has zero instances.

data "google_container_cluster" "existing" {
  count = local.byo_cluster ? 1 : 0

  name     = var.existing_cluster.name
  location = var.existing_cluster.location
  project  = local.project_id
}

locals {
  byo_cluster = var.existing_cluster != null
  project_id  = local.byo_cluster ? coalesce(var.existing_cluster.project_id, var.project_id) : var.project_id

  cluster_from_created = [for c in google_container_cluster.gke : {
    name                       = c.name
    location                   = c.location
    endpoint                   = c.endpoint
    certificate_authority_data = c.master_auth[0].cluster_ca_certificate
    workload_identity_pool     = "${var.project_id}.svc.id.goog"
    node_service_account_email = one(google_service_account.gke_nodes[*].email)
  }]

  cluster_from_existing = [for c in data.google_container_cluster.existing : {
    name                       = c.name
    location                   = c.location
    endpoint                   = c.endpoint
    certificate_authority_data = c.master_auth[0].cluster_ca_certificate
    # Read the pool off the live cluster rather than rebuilding the string, so
    # adopting a cluster with Workload Identity disabled surfaces as an empty
    # pool instead of an identity binding that silently never works.
    workload_identity_pool = try(c.workload_identity_config[0].workload_pool, "")
    # No clean equivalent: the cluster-level node_config is often just "default"
    # and per-pool service accounts are heterogeneous.
    node_service_account_email = null
  }]

  cluster = one(concat(local.cluster_from_created, local.cluster_from_existing))
}

# Adoption preconditions. Lifecycle preconditions rather than variable
# validations because this module is capped at Terraform 1.5.7 for GCP
# Marketplace / Infra Manager, which predates cross-variable validation — and
# null_resource rather than terraform_data because Marketplace rejects the
# builtin terraform provider.
resource "null_resource" "adopted_cluster_checks" {
  count = local.byo_cluster ? 1 : 0

  lifecycle {
    precondition {
      condition     = local.cluster.workload_identity_pool != ""
      error_message = "The adopted GKE cluster has Workload Identity disabled. Retool's operators authenticate to Google APIs through it; enable workload_identity_config on the cluster and GKE_METADATA on its node pools first."
    }
    precondition {
      condition     = !var.enable_gateway_api_check || try(data.google_container_cluster.existing[0].gateway_api_config[0].channel, "CHANNEL_DISABLED") != "CHANNEL_DISABLED"
      error_message = "The adopted GKE cluster has the Gateway API disabled. gcp-user-ingress needs the gke-l7-global-external-managed GatewayClass; set gateway_api_config.channel on the cluster, or set enable_gateway_api_check = false if you route ingress another way."
    }
  }
}
