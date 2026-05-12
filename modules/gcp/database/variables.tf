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
  description = "GCP region for the Cloud SQL instance"
}

# Unlike the AWS database module, there is no security group — Cloud SQL private IP
# access is governed by VPC peering (set up in the vpc module). Any pod in the VPC
# can reach Cloud SQL on its private IP once the vpc module's private_service_access
# connection is established.
variable "network_id" {
  type        = string
  description = "VPC network ID for Cloud SQL private IP (from the vpc module's network_id output)"
}

variable "db_purpose" {
  type        = string
  description = "Short identifier appended to the instance name (e.g. \"main\", \"workflows\")"
}

variable "tier" {
  type        = string
  description = "Cloud SQL machine tier (e.g. \"db-g1-small\", \"db-n1-standard-2\")"
  default     = "db-g1-small"
}

variable "postgres_version" {
  type        = string
  description = "PostgreSQL version string for Cloud SQL"
  default     = "POSTGRES_16"
}

variable "database_name" {
  type        = string
  description = "Name of the initial database to create"
  default     = "retool"
}

variable "master_username" {
  type        = string
  description = "Master database username"
  default     = "retool"
}

variable "disk_size_gb" {
  type        = number
  description = "Initial disk size in GB"
  default     = 20
}

variable "disk_autoresize" {
  type        = bool
  description = "Automatically grow disk when it reaches capacity"
  default     = true
}

variable "disk_autoresize_limit_gb" {
  type        = number
  description = "Maximum disk size in GB when autoresize is enabled (0 = unlimited)"
  default     = 200
}

# GCP equivalent of the AWS multi_az flag.
# "ZONAL" = single-zone, lower cost.
# "REGIONAL" = hot standby in a second zone, automatic failover.
variable "availability_type" {
  type        = string
  description = "Cloud SQL availability: ZONAL (single zone) or REGIONAL (cross-zone HA, equivalent to AWS multi_az)"
  default     = "ZONAL"
}

variable "point_in_time_recovery_enabled" {
  type        = bool
  description = "Enable point-in-time recovery (PITR) for the Cloud SQL instance. Recommended for production."
  default     = false
}

variable "backup_retention_count" {
  type        = number
  description = "Number of automated backups to retain"
  default     = 14
}

variable "backup_start_time" {
  type        = string
  description = "Daily backup start time (HH:MM in UTC)"
  default     = "05:00"
}

variable "maintenance_window_day" {
  type        = number
  description = "Day of the week for maintenance (1=Monday … 7=Sunday)"
  default     = 7
}

variable "maintenance_window_hour" {
  type        = number
  description = "Hour of the day for maintenance (0–23 UTC)"
  default     = 6
}

variable "deletion_protection" {
  type        = bool
  description = "Prevent Terraform from destroying the Cloud SQL instance"
  default     = false
}

variable "database_flags" {
  type = list(object({
    name  = string
    value = string
  }))
  description = "Custom database flags (equivalent to AWS RDS parameters)"
  default     = []
}

variable "tags" {
  type        = map(string)
  description = "Labels to apply to the Cloud SQL instance"
  default     = {}
}
