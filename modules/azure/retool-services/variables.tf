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

variable "aks" {
  type = object({
    cluster_name    = string
    oidc_issuer_url = string
  })
  description = "AKS cluster details. Use module.aks.cluster.name and .oidc_issuer_url."
}

variable "key_vault_id" {
  type        = string
  description = "ID of the shared Key Vault (from the VNet module)"
}

variable "key_vault_uri" {
  type        = string
  description = "URI of the shared Key Vault (e.g. https://name.vault.azure.net)"
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
