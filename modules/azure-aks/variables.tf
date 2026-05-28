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
    aks_subnet_id = string
  })
  description = <<-EOD
    VNet related inputs:
      aks_subnet_id: ID of the AKS node pool subnet
  EOD
}

variable "kubernetes_version" {
  type        = string
  description = "Kubernetes version for the AKS cluster"
  default     = "1.34"
}

variable "node_vm_size" {
  type        = string
  description = "VM size for the default node pool. See [Azure VM size documentation](https://learn.microsoft.com/en-us/azure/virtual-machines/sizes/general-purpose/d-family) or use `az vm list-skus` to find available sizes in your region. Recommended minimum is Standard_D4as_v4 or equivalent (4 cpu, 16Gi memory) for production Retool deployments."
  default     = "Standard_D4as_v6"
}

variable "node_os_disk_size_gb" {
  type        = number
  description = "OS disk size in GB for each node"
  default     = 100
}

variable "node_min_count" {
  type        = number
  description = "Minimum number of nodes in the default pool"
  default     = 2
}

variable "node_max_count" {
  type        = number
  description = "Maximum number of nodes in the default pool"
  default     = 8
}

variable "api_server_authorized_ip_ranges" {
  type        = list(string)
  description = "CIDR ranges allowed to reach the AKS API server. Empty list means unrestricted (public)."
  default     = []
}

variable "log_analytics_retention_days" {
  type        = number
  description = "Log Analytics workspace retention in days"
  default     = 30
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags applied to all resources created by this module"
}
