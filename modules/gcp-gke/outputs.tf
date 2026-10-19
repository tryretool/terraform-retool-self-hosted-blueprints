# Everything this module exports, enumerated explicitly. local.cluster resolves
# each cluster attribute from either the cluster we created or the one we
# adopted (see existing-cluster.tf); the rest are this module's own resources.
#
# The shape mirrors the AWS EKS module's cluster output for the fields the
# Kubernetes and Helm providers need, so provider.example.tf is recognizable.
locals {
  outputs = {
    name     = local.cluster.name
    location = local.cluster.location

    endpoint                   = local.cluster.endpoint
    certificate_authority_data = local.cluster.certificate_authority_data

    # GCP equivalent of the OIDC issuer URL. Used to bind k8s service accounts
    # to GCP service accounts via Workload Identity annotations.
    workload_identity_pool = local.cluster.workload_identity_pool

    # The node service account email. Callers that need to grant GCP API access to
    # application pods via Workload Identity will reference this. Null for an
    # adopted cluster, whose node pools this module does not own.
    node_service_account_email = local.cluster.node_service_account_email

    # Where the cluster's shared External Secrets Operator runs. Each Retool
    # deployment creates its own service account and GCP service account, and
    # names them on its namespaced SecretStore, so the controller reads only
    # what that deployment granted it.
    external_secrets_enabled         = var.enable_external_secrets
    external_secrets_namespace       = local.external_secrets.namespace
    external_secrets_service_account = local.external_secrets.service_account_name
  }
}

output "cluster" {
  description = "GKE cluster details"
  value       = local.outputs
}

output "outputs" {
  value       = local.outputs
  description = "Structured GKE cluster outputs for composition with downstream modules."
}
