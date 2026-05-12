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
  description = "GCP region for the cluster"
}

variable "network_name" {
  type        = string
  description = "Name of the VPC network (from the vpc module's network_name output)"
}

variable "subnet_name" {
  type        = string
  description = "Name of the subnet for GKE nodes (from the vpc module's subnet_name output)"
}

variable "pods_range_name" {
  type        = string
  description = "Name of the secondary IP range for pods (from the vpc module's pods_range_name output)"
}

variable "services_range_name" {
  type        = string
  description = "Name of the secondary IP range for services (from the vpc module's services_range_name output)"
}

# Setting location to a region (default) creates a regional cluster with masters
# replicated across 3 zones — equivalent to EKS which always runs multi-AZ masters.
# Setting to a zone (e.g. "us-central1-a") creates a cheaper zonal cluster.
variable "location" {
  type        = string
  description = "Cluster location: a region for multi-zone masters, or a zone for a zonal cluster"
  default     = ""
}

# If set, maps to min_master_version and disables the release_channel (the two are
# mutually exclusive in the Google provider). Leave empty to use release_channel instead.
variable "cluster_version" {
  type        = string
  description = "Specific GKE cluster version (e.g. \"1.32\"). If set, disables release_channel."
  default     = ""
}

# Ignored when cluster_version is set.
variable "release_channel" {
  type        = string
  description = "GKE release channel: RAPID, REGULAR, or STABLE"
  default     = "REGULAR"
}

variable "node_machine_type" {
  type        = string
  description = "Machine type for application nodes"
  default     = "n2-standard-4"
}

variable "node_disk_size_gb" {
  type        = number
  description = "Boot disk size in GB for each node"
  default     = 100
}

variable "node_min_count" {
  type        = number
  description = "Minimum number of nodes per zone in the node pool"
  default     = 1
}

variable "node_max_count" {
  type        = number
  description = "Maximum number of nodes per zone in the node pool"
  default     = 10
}

# When set, only connections from the listed CIDR blocks can reach the master endpoint.
# If empty, the master endpoint is publicly accessible from any IP.
variable "master_authorized_networks" {
  type = list(object({
    cidr_block   = string
    display_name = string
  }))
  description = "List of CIDR blocks allowed to reach the GKE master endpoint"
  default     = []
}

variable "deletion_protection" {
  type        = bool
  description = "Prevent Terraform from destroying the cluster"
  default     = false
}

variable "tags" {
  type        = map(string)
  description = "Labels to apply to GCP resources"
  default     = {}
}
