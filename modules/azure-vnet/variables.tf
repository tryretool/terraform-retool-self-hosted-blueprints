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
  description = "Azure region for all resources"
}

variable "vnet_cidr" {
  type        = string
  description = "CIDR block for the VNet"
  default     = "10.0.0.0/16"
}

variable "aks_subnet_cidr" {
  type        = string
  description = "CIDR for the AKS node pool subnet. With Azure CNI Overlay only node IPs consume this range."
  default     = "10.0.0.0/20"
}

variable "postgres_subnet_cidr" {
  type        = string
  description = "CIDR for the PostgreSQL Flexible Server delegated subnet"
  default     = "10.0.16.0/24"
}

variable "agc_subnet_cidr" {
  type        = string
  description = "CIDR for the Application Gateway for Containers association subnet"
  default     = "10.0.17.0/24"
}

variable "nsg_rules" {
  type = list(object({
    name                       = string
    priority                   = number
    direction                  = string
    access                     = string
    protocol                   = string
    source_address_prefix      = string
    destination_address_prefix = string
    source_port_range          = string
    destination_port_range     = string
  }))
  description = "Custom NSG rules for the AKS subnet. Defaults allow HTTP and HTTPS inbound."
  default = [
    {
      name                       = "AllowHTTP"
      priority                   = 100
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_address_prefix      = "*"
      destination_address_prefix = "*"
      source_port_range          = "*"
      destination_port_range     = "80"
    },
    {
      name                       = "AllowHTTPS"
      priority                   = 101
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_address_prefix      = "*"
      destination_address_prefix = "*"
      source_port_range          = "*"
      destination_port_range     = "443"
    }
  ]
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags applied to all resources created by this module"
}
