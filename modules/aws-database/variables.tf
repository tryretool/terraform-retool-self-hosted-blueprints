variable "prefix" {
  type        = string
  description = "Prefix for resource names"
}

variable "db_purpose" {
  type        = string
  description = "the purpose of this db"
}

variable "vpc" {
  type = object({
    vpc_id             = string
    private_subnet_ids = list(string)
  })
  description = <<-EOD
    VPC related inputs:
      vpc_id: ID of the VPC where the database security group is created
      private_subnet_ids: List of private subnet IDs for the database subnet group
  EOD
}

variable "eks" {
  type = object({
    node_security_group_id = string
  })
  description = <<-EOD
    EKS related inputs:
      node_security_group_id: Security group ID of the EKS nodes, used to allow ingress to the database
  EOD
}

variable "vpc_security_group_ids" {
  type        = list(string)
  description = "List of VPC security groups to associate to the cluster in addition to the SG we create in this module"
  default     = []
}

variable "create_db_subnet_group" {
  type        = bool
  description = "Whether to create a database subnet group"
  default     = true
}

# cluster
variable "instance_class" {
  type        = string
  description = "Instance type to use at master instance"
}

variable "engine" {
  type        = string
  default     = "postgres"
  description = "The name of the database engine to be used for this DB cluster"
}

variable "engine_version" {
  type        = string
  default     = "16.8"
  description = "The database engine version"
}

variable "family" {
  type        = string
  description = "The family of the DB parameter group"
  default     = "postgres16"
}

variable "major_engine_version" {
  type        = string
  description = "Specifies the major version of the engine that this option group should be associated with"
  default     = "16"
}

variable "allocated_storage" {
  type        = number
  description = "The allocated storage in gigabytes"
  default     = 20
}

variable "master_username" {
  type        = string
  description = "Username for the master DB user"
  default     = "retool"
}

variable "database_name" {
  type        = string
  description = "Name for an automatically created database on cluster creation"
  default     = "retool"
}

variable "port" {
  type        = number
  description = "The port on which the DB accepts connections"
  default     = 5432
}

variable "storage_encrypted" {
  type        = bool
  description = "Specifies whether the DB cluster is encrypted"
  default     = true
}

variable "storage_type" {
  type        = string
  description = "One of 'standard' (magnetic), 'gp2' (general purpose SSD), 'gp3' (new generation of general purpose SSD), or 'io1' (provisioned IOPS SSD)."
  default     = "gp3"
}

variable "max_allocated_storage" {
  type        = number
  description = "Description: Specifies the value for Storage Autoscaling"
  default     = 200
}

variable "iops" {
  type        = number
  description = "The amount of provisioned IOPS. Setting this implies a storage_type of 'io1' or `gp3`"
  # our default should've been 3000 here, which is the default free tier limit for gp3. But there's a bug in the provider that makes it fail
  # if we set a number here when the allocated storage is < 400GB
  default = null
}

variable "custom_kms_key_arn" {
  type        = string
  description = "The ARN for the KMS encryption key. When specifying kms_key_id, storage_encrypted needs to be set to true"
  default     = null
}

variable "apply_immediately" {
  type        = bool
  description = "Specifies whether any cluster modifications are applied immediately, or during the next maintenance window"
  default     = true
}

variable "create_monitoring_role" {
  type        = bool
  description = "Create IAM role with a defined name that permits RDS to send enhanced monitoring metrics to CloudWatch Logs"
  default     = true
}

variable "monitoring_interval" {
  type        = number
  description = "The interval, in seconds, between points when enhanced monitoring metrics are collected for the DB instance. To disable collecting Enhanced Monitoring metrics, specify 0. The default is 0. Valid Values: 0, 1, 5, 10, 15, 30, 60"
  default     = 30
}

variable "monitoring_role_arn" {
  type        = string
  description = "IAM role used by RDS to send enhanced monitoring metrics to CloudWatch"
  default     = ""
}

variable "monitoring_role_name" {
  type        = string
  description = "Friendly name of the monitoring role"
  default     = "rds-monitoring-role"
}

variable "monitoring_role_name_full" {
  type        = string
  description = "Full name of the monitoring role"
  default     = null
}

variable "maintenance_window" {
  type        = string
  description = "The window to perform maintenance in. Syntax: 'ddd:hh24:mi-ddd:hh24:mi'. Eg: 'Mon:00:00-Mon:03:00'"
  default     = "Sun:06:00-Sun:07:00"
}

variable "backup_window" {
  type        = string
  description = "The daily time range (in UTC) during which automated backups are created if they are enabled. Example: '09:46-10:16'. Must not overlap with maintenance_window"
  default     = "05:00-06:00"
}

variable "parameters" {
  type        = list(map(string))
  description = "A list of DB parameters (map) to apply"
  default     = []
}

variable "options" {
  type        = any
  description = "A list of Options to apply"
  default     = []
}

variable "create_cloudwatch_log_group" {
  type        = bool
  default     = true
  description = "Determines whether a CloudWatch log group is created for each `enabled_cloudwatch_logs_exports`"
}

variable "performance_insights_enabled" {
  type        = bool
  default     = true
  description = "Specifies whether Performance Insights are enabled"
}

variable "performance_insights_retention_period" {
  type        = number
  description = "The amount of time in days to retain Performance Insights data. Either 7 (7 days) or 731 (2 years)"
  default     = 7
}

variable "enabled_cloudwatch_logs_exports" {
  type        = list(string)
  default     = ["postgresql", "upgrade"]
  description = "Set of log types to export to cloudwatch. If omitted, no logs will be exported. The following log types are supported: `audit`, `error`, `general`, `slowquery`, `postgresql`"
}

variable "backup_retention_period" {
  type        = number
  description = "Number of days to retain backups for"
  default     = 14
}

variable "default_tags" {
  type        = map(string)
  description = "Default tags applied to all taggable resources. Includes service identification by default."
  default = {
    "service" = "retool"
  }
}

variable "tags" {
  type        = map(string)
  description = "Extra tags merged on top of default_tags."
  default     = {}
}

variable "deletion_protection" {
  type        = bool
  description = "If the DB instance should have deletion protection enabled. The database can't be deleted when this value is set to `true`"
  default     = false
}

variable "skip_final_snapshot" {
  type        = bool
  description = "If true, no final snapshot is created when the DB instance is deleted. Set to false in production to preserve a recovery point."
  default     = true
}

variable "publicly_accessible" {
  type        = bool
  description = "Whether the DB instance should be publicly accessible"
  default     = false
}

variable "identifier" {
  type        = string
  description = "Name of the rds db. Defaults to {var.prefix}-rds"
  default     = null
}

variable "replicate_source_db" {
  type        = string
  description = "The source db to replicate from"
  default     = null
}

variable "license_model" {
  description = "License model information for this DB instance. Optional, but required for some DB engines, i.e. Oracle SE1"
  type        = string
  default     = null
}

variable "multi_az" {
  description = "Specifies if the RDS instance is multi-AZ"
  type        = bool
  default     = false
}

# ---------------------------------------------------------------------------
# Adopting an existing database
#
# These exist so a database created by other tooling — a CloudFormation stack,
# say — can be imported into this module without Terraform replacing it or
# changing how it authenticates. All of them default to this module's normal
# behavior, so they are no-ops unless you are importing.
# ---------------------------------------------------------------------------

variable "manage_master_user_password" {
  type        = bool
  description = <<-EOT
    Whether RDS manages the master user password in Secrets Manager, rotating it
    and owning the secret. This is the default for databases this module creates.

    Set false when importing a database whose password is managed elsewhere:
    Terraform then leaves the existing password alone, rather than having RDS
    generate a new one — which would immediately lock out anything still reading
    the old credentials. Supply master_user_secret_arn alongside it.
  EOT
  default     = true
}

variable "master_user_secret_arn" {
  type        = string
  description = "ARN of the Secrets Manager secret holding the master credentials, overriding the `master_user_secret_arn` output. Required when manage_master_user_password is false, because RDS only populates that ARN for secrets it manages itself."
  default     = null

  validation {
    condition     = var.manage_master_user_password || var.master_user_secret_arn != null
    error_message = "master_user_secret_arn is required when manage_master_user_password is false: RDS does not report a secret ARN for a password it does not manage, so downstream modules would have nothing to read the database credentials from."
  }
}

variable "security_group_name" {
  type        = string
  description = <<-EOT
    Exact name of the database security group. Leave null and this module names
    it "{identifier}-rds-sg" with a unique suffix.

    Set it to the existing group's name when importing one: a security group's
    name cannot be changed in place, so a mismatch here makes Terraform destroy
    and recreate the group, taking every rule on it with it.
  EOT
  default     = null
}

variable "manage_security_group_rules" {
  type        = bool
  description = <<-EOT
    Whether this module manages the rules on the database security group (ingress
    from the EKS nodes, and all egress).

    Set false when importing a security group whose existing rules must survive —
    Terraform would otherwise delete every rule it doesn't know about, and fail
    on the ones it would duplicate. You are then responsible for declaring the
    rules yourself, including access for the EKS nodes.
  EOT
  default     = true
}

variable "db_subnet_group_name" {
  type        = string
  description = "Exact name of the DB subnet group. Leave null and this module names it after the identifier with a unique suffix. As with security_group_name, set it to the existing name when importing, since the name cannot be changed in place."
  default     = null
}

variable "create_db_parameter_group" {
  type        = bool
  description = "Whether to create a DB parameter group for this instance. Set false when importing a database that should keep the parameter group it already uses; combine with parameter_group_name to name it."
  default     = true
}

variable "parameter_group_name" {
  type        = string
  description = "Name of an existing DB parameter group to attach. Only used when create_db_parameter_group is false."
  default     = null
}
