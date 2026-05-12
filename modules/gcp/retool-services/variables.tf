variable "prefix" {
  type = string
}

variable "project_id" {
  type = string
}

variable "region" {
  type = string
}

# Only fields used by this module. Configure kubernetes/helm providers in the root
# with module.gke.cluster.endpoint and certificate_authority_data when needed.
variable "gke" {
  type = object({
    cluster_name     = string
    cluster_location = string
    # cluster_endpoint is "known after apply" from the GKE cluster. Passing it here
    # ensures that Workload Identity IAM bindings (which reference the pool
    # {project_id}.svc.id.goog created by GKE) are not applied until the cluster exists.
    cluster_endpoint = string
  })
  description = "GKE cluster details. Use module.gke.cluster.name, .location, and .endpoint."
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Labels applied to GCP resources created by this module."
}

variable "db_credentials_secret_name" {
  type        = string
  description = "Name of the GCP Secret Manager secret for the database password (e.g. module.db-main.db_instance_master_user_secret_name)."
}

variable "encryption_key_secret_name" {
  type        = string
  default     = null
  description = "Name of an existing Secret Manager secret to use as the Retool encryption key. If null, a random key is generated at retool-{prefix}-encryption-key. Provide a value to support data migration from an existing deployment."
}
