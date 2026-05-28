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
  type = object({
    address                 = string
    port                    = number
    name                    = string
    username                = string
    master_user_secret_name = string
  })
  description = "Database outputs (e.g. module.db-main.outputs). Connection info is used to build the agent sandbox Postgres URL when enable_agent_sandbox is true."
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

variable "license_key" {
  type        = string
  default     = null
  sensitive   = true
  description = "Retool license key. When set, stored in Secret Manager and synced to a K8s Secret via ESO. Leave null for free-tier mode."
}

variable "enable_agent_sandbox" {
  type        = bool
  default     = false
  description = "When true, generates agent sandbox secrets (JWT keypair, encryption key, API secret, Postgres URL) synced to K8s via ESO."
}

variable "enable_rr_gcs" {
  type        = bool
  default     = false
  description = "Whether to create a GCS bucket and HMAC keys for Retool Remote Repository storage. Uses GCS S3-compatible API."
}
