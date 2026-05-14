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

variable "domain_name" {
  type        = string
  description = "Domain name for the Retool deployment (e.g. retool.example.com)"
}

variable "vnet" {
  type = object({
    appgw_subnet_id = string
  })
  description = <<-EOD
    VNet related inputs:
      appgw_subnet_id: ID of the Application Gateway dedicated subnet
  EOD
}

variable "aks" {
  type = object({
    oidc_issuer_url = string
  })
  description = "AKS cluster outputs for Workload Identity federation (e.g. module.aks.outputs)."
}

variable "retool_service_port" {
  type        = number
  description = "Port on the Kubernetes Service that serves Retool traffic"
  default     = 3000
}

variable "enable_https" {
  type        = bool
  description = <<-EOT
    When true, deploy cert-manager and provision a Let's Encrypt TLS certificate
    via DNS-01 challenge using Azure DNS. The Application Gateway terminates TLS
    on port 443 with an HTTP-to-HTTPS redirect.
    When false, the Application Gateway serves Retool on HTTP port 80 only —
    suitable for initial apply before DNS delegation.
  EOT
  default     = false
}

variable "enable_agent_sandbox_proxy" {
  type        = bool
  default     = false
  description = "When true, outputs the agent sandbox proxy URL at agent-proxy.<domain_name>. Routing is handled by the retool-helm chart Ingress, not Terraform."
}

variable "agent_sandbox_proxy_port" {
  type        = number
  default     = 3019
  description = "Port on the agent sandbox proxy Kubernetes Service."
}

variable "agent_sandbox_proxy_service_name" {
  type        = string
  default     = "retool-agent-sandbox-proxy"
  description = "Name of the Kubernetes Service fronting the agent sandbox proxy pods."
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags applied to all resources created by this module"
}
