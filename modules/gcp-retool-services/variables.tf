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

# --- Namespaces ---
# Both the Retool application namespace and the supporting-services namespace are
# computed here (single source of truth) and exported via outputs.tf so the
# retool-helm and gcp-user-ingress modules consume the same names. Leave null for
# the default prefixed names; set explicitly to target pre-existing namespaces in
# a shared cluster.

variable "retool_namespace" {
  type        = string
  default     = null
  description = "Namespace for the Retool application and the K8s objects that live beside it (ExternalSecrets, the namespaced SecretStore). When null, defaults to \"<prefix>-retool\"."
}

variable "services_namespace" {
  type        = string
  default     = null
  description = "Namespace for Retool's supporting operators (External Secrets Operator, reloader). When null, defaults to \"<prefix>-retool-services\"."
}

variable "create_namespaces" {
  type        = bool
  default     = true
  description = "Whether this module creates the retool and services namespaces. Set false in shared clusters where the namespaces are provisioned out of band."
}

# --- Per-release enable toggles ---
# All default true to preserve the from-scratch all-inclusive behavior. Flip the
# cluster-singleton operators off when deploying into a shared cluster that
# already runs them.

variable "enable_external_secrets" {
  type        = bool
  default     = true
  description = "Whether to install the External Secrets Operator (and its Workload Identity wiring). Disable in shared clusters that already run ESO; the SecretStore and ExternalSecret resources are still created so the platform's ESO reconciles them."
}

variable "create_external_secrets" {
  type        = bool
  default     = true
  description = "Whether to create the ESO ExternalSecret resources that sync cloud secrets into K8s Secrets in the retool namespace. Disable if you manage the ExternalSecret resources out of band. Independent of enable_external_secrets (which controls the operator itself)."
}

variable "enable_reloader" {
  type        = bool
  default     = true
  description = "Whether to install Stakater reloader. When enabled it is scoped to only watch the retool namespace."
}

variable "install_crds" {
  type        = bool
  default     = true
  description = "Whether the bundled External Secrets Operator installs its CRDs. Set false in shared clusters where these cluster-scoped CRDs are already managed out of band."
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
  description = "Retool license key. When set, stored in Secret Manager and synced to a K8s Secret via ESO. Leave null for free-tier mode. Mutually exclusive with license_key_secret_path."
}

variable "license_key_secret_path" {
  type        = string
  default     = null
  description = "Full GCP Secret Manager secret name (path) of an existing secret holding the Retool license key. When set, ESO is granted read access and syncs it to the license-key K8s Secret, which retool-helm wires to config.licenseKeySecretName/licenseKeySecretKey. Mutually exclusive with license_key (which creates a managed secret instead)."
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

variable "external_secrets_chart" {
  type = object({
    repository       = string
    version          = string
    image_repository = string
    image_tag        = string
  })
  default = {
    repository       = "https://charts.external-secrets.io"
    version          = "2.8.0"
    image_repository = "ghcr.io/external-secrets/external-secrets"
    image_tag        = "v2.8.0"
  }
  description = "Where to fetch the External Secrets chart and image. Defaults to upstream. Override to serve both from a private registry, which GCP Marketplace requires and restricted-egress installs need. Use an oci:// URL for repository when the chart lives in an OCI registry. Keep version and image_tag in step: the chart and the operator are released together, and a mismatch is not tested upstream."
}

variable "reloader_chart" {
  type = object({
    repository       = string
    version          = string
    image_repository = string
    image_tag        = string
  })
  default = {
    repository       = "https://stakater.github.io/stakater-charts"
    version          = "2.2.14"
    image_repository = "ghcr.io/stakater/reloader"
    image_tag        = "v1.4.19"
  }
  description = "Where to fetch the Reloader chart and image. Defaults to upstream. Override to serve both from a private registry. Note the chart and app versions differ (chart 2.2.14 ships app v1.4.19)."
}
