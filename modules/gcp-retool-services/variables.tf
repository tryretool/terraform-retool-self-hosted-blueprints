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
    name     = string
    location = string
    # endpoint is "known after apply" from the GKE cluster. Passing it here
    # ensures that Workload Identity IAM bindings (which reference the pool
    # {project_id}.svc.id.goog created by GKE) are not applied until the cluster exists.
    endpoint = string
  })
  description = "GKE cluster outputs (e.g. module.gke.outputs)."
}

variable "db" {
  type        = object({ master_user_secret_name = string })
  description = "Database outputs (e.g. module.db-main.outputs). Only master_user_secret_name is used."
}

variable "default_tags" {
  type        = map(string)
  default     = { "service" = "retool" }
  description = "Default labels applied to all resources. Merged with var.tags (tags take precedence)."
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Labels applied to GCP resources created by this module."
}

variable "encryption_key_secret_name" {
  type        = string
  default     = null
  description = "Name of an existing Secret Manager secret to use as the Retool encryption key. If null, a random key is generated at retool-{prefix}-encryption-key. Provide a value to support data migration from an existing deployment."
}
