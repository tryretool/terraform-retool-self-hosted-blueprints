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

variable "db_purpose" {
  type        = string
  description = "Short identifier for this database (e.g. 'main', 'workflows'). Used in resource naming."
  default     = "main"
}

variable "db_password_wo_version" {
  type        = number
  default     = 1
  description = "Version counter for the generated database password secret value (write-only). Increment to force Terraform to rewrite it."
}

variable "vnet" {
  type = object({
    vnet_id            = string
    postgres_subnet_id = string
    key_vault_id       = string
  })
  description = <<-EOD
    VNet related inputs:
      vnet_id: ID of the VNet (for Private DNS Zone link)
      postgres_subnet_id: ID of the delegated subnet for PostgreSQL Flexible Server
      key_vault_id: ID of the Key Vault to store the database password
  EOD
}

variable "postgres_version" {
  type        = string
  description = "PostgreSQL major version"
  default     = "16"
}

variable "sku_name" {
  type        = string
  description = "SKU for the Flexible Server (e.g. B_Standard_B1ms for dev, GP_Standard_D2s_v3 for prod)"
  default     = "GP_Standard_D2s_v3"
}

variable "storage_mb" {
  type        = number
  description = "Storage in MB for the Flexible Server"
  default     = 131072 # 128 GB
}

variable "auto_grow_enabled" {
  type        = bool
  description = "Enable automatic storage growth"
  default     = true
}

variable "high_availability_mode" {
  type        = string
  description = "HA mode: Disabled, SameZone, or ZoneRedundant"
  default     = "Disabled"

  validation {
    condition     = contains(["Disabled", "SameZone", "ZoneRedundant"], var.high_availability_mode)
    error_message = "Must be Disabled, SameZone, or ZoneRedundant."
  }
}

variable "backup_retention_days" {
  type        = number
  description = "Backup retention period in days"
  default     = 14
}

variable "master_username" {
  type        = string
  description = "Master database username"
  default     = "retool"
}

variable "database_name" {
  type        = string
  description = "Name of the database to create"
  default     = "retool"
}

variable "deletion_protection" {
  type        = bool
  description = "Prevent Terraform from destroying the database"
  default     = false
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags applied to all resources created by this module"
}
