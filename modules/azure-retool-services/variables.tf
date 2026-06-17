variable "prefix" {
  type        = string
  description = "Prefix for all resource names"
}

variable "resource_group_name" {
  type        = string
  description = "Name of the Azure resource group"
}

variable "location" {
  type        = string
  description = "Azure region"
}

variable "vnet" {
  type = object({
    key_vault_id  = string
    key_vault_uri = string
  })
  description = <<-EOD
    VNet related inputs:
      key_vault_id: ID of the shared Key Vault
      key_vault_uri: URI of the shared Key Vault (e.g. https://name.vault.azure.net)
  EOD
}

variable "aks" {
  type = object({
    name            = string
    oidc_issuer_url = string
  })
  description = "AKS cluster outputs (e.g. module.aks.outputs)."
}

variable "db" {
  type = object({
    address            = string
    port               = number
    name               = string
    username           = string
    master_secret_name = string
  })
  description = "Database outputs (e.g. module.db-main.outputs). Connection info is used to build the agent sandbox Postgres URL when enable_agent_sandbox is true."
}

# --- Namespaces ---
# Both the Retool application namespace and the supporting-services namespace are
# computed here (single source of truth) and exported via outputs.tf so the
# retool-helm and azure-user-ingress modules consume the same names. Leave null
# for the default prefixed names; set explicitly to target pre-existing
# namespaces in a shared cluster.

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

variable "encryption_key_secret_name" {
  type        = string
  default     = null
  description = "Name of an existing Key Vault secret to use as the Retool encryption key. If null, a random key is generated."
}

variable "license_key" {
  type        = string
  default     = null
  sensitive   = true
  description = "Retool license key. If provided, stored in Key Vault and synced to K8s. Mutually exclusive with license_key_secret_path."
}

variable "license_key_secret_path" {
  type        = string
  default     = null
  description = "Name of an existing Key Vault secret (in the shared vault) holding the Retool license key. When set, ESO syncs it to the license-key K8s Secret, which retool-helm wires to config.licenseKeySecretName/licenseKeySecretKey. Mutually exclusive with license_key (which creates a managed secret instead)."
}

# --- Write-only secret version control ---
# These Key Vault secrets use write-only (value_wo) values so the contents are
# never stored in Terraform state and out-of-band edits are not reverted as
# drift. Bump the corresponding *_wo_version to force Terraform to (re)write the
# managed value.

variable "encryption_key_wo_version" {
  type        = number
  default     = 1
  description = "Version counter for the generated encryption-key secret value. Increment to force Terraform to rewrite it."
}

variable "jwt_secret_wo_version" {
  type        = number
  default     = 1
  description = "Version counter for the generated jwt-secret secret value. Increment to force Terraform to rewrite it."
}

variable "extra_env_vars_wo_version" {
  type        = number
  default     = 1
  description = "Version counter for the extra-env-vars secret seed value. Increment to force Terraform to overwrite out-of-band edits back to the empty object."
}

variable "license_key_wo_version" {
  type        = number
  default     = 1
  description = "Version counter for the license-key secret value (only used when license_key is set). Increment to force Terraform to rewrite it."
}

variable "enable_agent_sandbox" {
  type        = bool
  default     = false
  description = "When true, generates agent sandbox secrets (JWT keypair, encryption key, API secret, Postgres URL) synced to K8s via ESO."
}

variable "enable_rr_blob" {
  type        = bool
  default     = false
  description = "Whether to create an Azure Storage Account and Blob container for Retool Remote Repository storage."
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags applied to all resources created by this module"
}
