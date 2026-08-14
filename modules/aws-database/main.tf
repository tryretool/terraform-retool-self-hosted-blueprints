locals {
  rds_cluster_identifier = var.identifier != null ? var.identifier : "${var.prefix}-${var.db_purpose}"
  all_tags               = merge(var.default_tags, var.tags)
}

module "rds_cluster" {
  source  = "terraform-aws-modules/rds/aws"
  version = "7.1.0"

  identifier = local.rds_cluster_identifier

  engine               = var.engine
  engine_version       = var.engine_version
  family               = var.family               # DB parameter group
  major_engine_version = var.major_engine_version # DB option group
  instance_class       = var.instance_class

  create_db_parameter_group = var.create_db_parameter_group
  parameter_group_name      = var.parameter_group_name
  storage_type              = var.storage_type
  iops                      = var.storage_type == "gp2" ? null : var.iops
  allocated_storage         = var.allocated_storage
  multi_az                  = var.multi_az

  subnet_ids             = var.vpc.private_subnet_ids
  vpc_security_group_ids = concat([module.main_rds_sg.security_group_id], var.vpc_security_group_ids)

  # only set these for primaries
  db_name  = var.replicate_source_db == null ? var.database_name : null
  username = var.replicate_source_db == null ? var.master_username : null
  port     = var.port

  manage_master_user_password = var.manage_master_user_password

  replicate_source_db = var.replicate_source_db
  license_model       = var.license_model
  publicly_accessible = var.publicly_accessible

  storage_encrypted = var.storage_encrypted
  kms_key_id        = var.custom_kms_key_arn

  performance_insights_enabled          = var.performance_insights_enabled
  performance_insights_retention_period = var.performance_insights_retention_period
  performance_insights_kms_key_id       = var.custom_kms_key_arn
  create_monitoring_role                = var.create_monitoring_role
  monitoring_interval                   = var.monitoring_interval
  monitoring_role_arn                   = var.monitoring_role_arn
  monitoring_role_name                  = var.monitoring_role_name_full != null ? var.monitoring_role_name_full : "${var.prefix}-${var.monitoring_role_name}"
  create_cloudwatch_log_group           = var.create_cloudwatch_log_group
  enabled_cloudwatch_logs_exports       = var.enabled_cloudwatch_logs_exports

  backup_retention_period = var.replicate_source_db == null ? var.backup_retention_period : 0
  maintenance_window      = var.maintenance_window
  backup_window           = var.backup_window

  # DB subnet group
  create_db_subnet_group = var.create_db_subnet_group
  # A subnet group's name is fixed at creation, so an imported group has to be
  # named exactly rather than given the usual unique suffix.
  db_subnet_group_name            = var.db_subnet_group_name
  db_subnet_group_use_name_prefix = var.db_subnet_group_name == null

  # Database Deletion Protection
  deletion_protection = var.deletion_protection

  parameters = var.parameters
  options    = var.options

  skip_final_snapshot = var.skip_final_snapshot
  apply_immediately   = var.apply_immediately

  tags = local.all_tags

  max_allocated_storage = var.max_allocated_storage
}

module "main_rds_sg" {
  source      = "terraform-aws-modules/security-group/aws"
  version     = "4.13.1"
  name        = coalesce(var.security_group_name, "${local.rds_cluster_identifier}-rds-sg")
  description = "SG for RDS Instance communication within VPC"
  vpc_id      = var.vpc.vpc_id

  # A security group's name is fixed at creation. Normally we append a unique
  # suffix; an imported group has to keep the name it already has, or Terraform
  # replaces it and every rule on it goes with it.
  use_name_prefix = var.security_group_name == null

  tags = local.all_tags

  computed_ingress_with_source_security_group_id = var.manage_security_group_rules ? [
    {
      rule                     = "postgresql-tcp"
      source_security_group_id = var.eks.node_security_group_id
      description              = "Allow EKS cluster to communicate with RDS"
    }
  ] : []
  number_of_computed_ingress_with_source_security_group_id = var.manage_security_group_rules ? 1 : 0

  egress_rules = var.manage_security_group_rules ? ["all-all"] : []

  create_timeout = "15m"
  delete_timeout = "45m"
}
