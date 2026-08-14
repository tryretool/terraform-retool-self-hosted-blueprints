locals {
  outputs = {
    arn                   = module.rds_cluster.db_instance_arn
    endpoint              = module.rds_cluster.db_instance_endpoint
    address               = module.rds_cluster.db_instance_address
    engine                = module.rds_cluster.db_instance_engine
    id                    = module.rds_cluster.db_instance_identifier
    name                  = module.rds_cluster.db_instance_name
    username              = nonsensitive(module.rds_cluster.db_instance_username)
    port                  = module.rds_cluster.db_instance_port
    subnet_group_id       = module.rds_cluster.db_subnet_group_id
    cloudwatch_log_groups = module.rds_cluster.db_instance_cloudwatch_log_groups
    security_group_id     = module.main_rds_sg.security_group_id
    # RDS only reports this for secrets it manages itself, so an adopted database
    # with an externally-managed password supplies its secret ARN directly.
    master_user_secret_arn = (
      var.master_user_secret_arn != null
      ? var.master_user_secret_arn
      : module.rds_cluster.db_instance_master_user_secret_arn
    )
  }
}

output "arn" {
  description = "The ARN of the RDS instance"
  value       = local.outputs.arn
}

output "endpoint" {
  description = "The connection endpoint"
  value       = local.outputs.endpoint
}

output "address" {
  description = "The address of the RDS instance"
  value       = local.outputs.address
}

output "engine" {
  description = "The database engine"
  value       = local.outputs.engine
}

output "id" {
  description = "The RDS instance identifier (ID)"
  value       = local.outputs.id
}

output "name" {
  description = "The database name"
  value       = local.outputs.name
}

output "username" {
  description = "The master username for the database"
  value       = local.outputs.username
}

output "port" {
  description = "The database port"
  value       = local.outputs.port
}

output "subnet_group_id" {
  description = "The db subnet group name"
  value       = local.outputs.subnet_group_id
}

output "cloudwatch_log_groups" {
  description = "Map of CloudWatch log groups created and their attributes"
  value       = local.outputs.cloudwatch_log_groups
}

output "security_group_id" {
  description = "ID of the security group attached to the RDS instance by this module."
  value       = local.outputs.security_group_id
}

output "master_user_secret_arn" {
  description = "ARN of the Secrets Manager secret holding the RDS master user credentials (managed by RDS)."
  value       = local.outputs.master_user_secret_arn
}

output "outputs" {
  value       = local.outputs
  description = "Structured database outputs for composition with downstream modules."
}
