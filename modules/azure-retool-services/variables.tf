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

variable "db_credentials_secret_name" {
  type        = string
  description = "Name of the Key Vault secret for the database password (from the database module)"
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
  description = "Retool license key. If provided, stored in Key Vault and synced to K8s."
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags applied to all resources created by this module"
}
