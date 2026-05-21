variable "prefix" {
  type        = string
  description = "Prefix for resource names."
}

variable "project_id" {
  type        = string
  description = "GCP project ID."
}

variable "region" {
  type        = string
  description = "GCP region."
}

variable "domain_name" {
  type        = string
  description = "Domain name for the Retool deployment (e.g. \"retool.example.com\"). Used for the Cloud DNS zone, Certificate Manager certificate, and Gateway routing."
}

variable "default_tags" {
  type        = map(string)
  default     = { "service" = "retool" }
  description = "Default labels applied to all resources. Merged with var.tags (tags take precedence)."
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Labels applied to GCP resources."
}

variable "enable_agent_sandbox_proxy" {
  type        = bool
  default     = false
  description = "When true, outputs the agent sandbox proxy URL at agent-proxy.<domain_name>. Routing is handled by the retool-helm chart HTTPRoute, not Terraform."
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
