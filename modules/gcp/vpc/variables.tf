variable "prefix" {
  type        = string
  description = "Prefix for all resource names"
}

variable "project_id" {
  type        = string
  description = "GCP project ID"
}

variable "region" {
  type        = string
  description = "GCP region for subnets, Cloud NAT, and Cloud Router"
}

variable "subnet_ip_range" {
  type        = string
  description = "Primary subnet CIDR range (used by GKE nodes)"
  default     = "10.0.0.0/20"
}

variable "pods_ip_range" {
  type        = string
  description = "Secondary CIDR range for GKE pod IPs (VPC-native alias IPs)"
  default     = "10.1.0.0/16"
}

variable "services_ip_range" {
  type        = string
  description = "Secondary CIDR range for GKE service ClusterIPs"
  default     = "10.2.0.0/20"
}

# A /24 is sufficient; Cloud SQL private service access requires a range of at least /24.
# Unlike AWS, this is not a separate subnet — it's a reserved range for the VPC peering
# connection to Google-managed services (Cloud SQL). Any pod in the primary subnet can
# reach Cloud SQL on its private IP once this peering is established.
#
# Note: this is Private Service Access (VPC peering to Google-managed services), NOT
# Private Service Connect (which uses forwarding rules/endpoints). The names are similar
# but they are different GCP networking features.
variable "private_service_access_ip_range" {
  type        = string
  description = "IP range (/24 or larger) reserved for Google-managed service peering (required for Cloud SQL private IP)"
  default     = "10.3.0.0/24"

  validation {
    condition     = can(cidrhost(var.private_service_access_ip_range, 0))
    error_message = "Must be a valid CIDR block (e.g. \"10.3.0.0/24\")."
  }
}
