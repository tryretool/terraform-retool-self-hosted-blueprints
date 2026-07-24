locals {
  outputs = {
    name     = google_container_cluster.gke.name
    location = google_container_cluster.gke.location

    # Used to configure kubernetes/helm provider — same key names as EKS module output.
    endpoint                   = google_container_cluster.gke.endpoint
    certificate_authority_data = google_container_cluster.gke.master_auth[0].cluster_ca_certificate

    # GCP equivalent of the OIDC issuer URL. Used to bind k8s service accounts
    # to GCP service accounts via Workload Identity annotations.
    workload_identity_pool = "${var.project_id}.svc.id.goog"

    # The node service account email. Callers that need to grant GCP API access to
    # application pods via Workload Identity will reference this.
    node_service_account_email = google_service_account.gke_nodes.email
  }
}

# The cluster output shape mirrors the AWS EKS module's cluster output for the
# fields used by Kubernetes and Helm providers, so provider.tf.example is recognizable.
output "cluster" {
  description = "GKE cluster details"
  value       = local.outputs
}

output "outputs" {
  value       = local.outputs
  description = "Structured GKE cluster outputs for composition with downstream modules."
}
