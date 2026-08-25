# Adopts the databases your CloudFormation stack already runs, instead of
# creating them with the aws-database module.
#
# These are referenced, never modified. The Retool database in particular holds
# every app, query, resource and user in your deployment; Terraform reads its
# connection details and nothing more. The running ECS deployment keeps its own
# access throughout — this stack adds an ingress rule for the new EKS nodes and
# leaves every existing rule alone.

data "aws_db_instance" "retool" {
  db_instance_identifier = var.retool_db.instance_identifier
}

locals {
  # Same shape as module.db-main.outputs in the all-inclusive examples, so the
  # downstream modules take it unchanged.
  #
  # master_user_secret_arn names the secret External Secrets Operator reads the
  # password from. For a database this repo creates, that would be the secret
  # RDS manages and rotates; here it is the secret CloudFormation generated,
  # whose {"username": ..., "password": ...} shape ESO reads the same way.
  db = {
    address                = data.aws_db_instance.retool.address
    port                   = data.aws_db_instance.retool.port
    name                   = data.aws_db_instance.retool.db_name
    username               = data.aws_db_instance.retool.master_username
    master_user_secret_arn = var.retool_db.credentials_secret_id
  }
}

# The CloudFormation stack's database security group only admits its own ECS
# tasks. Retool pods reach Postgres from the EKS node security group, so it
# needs a rule of its own. This is additive — the existing ECS ingress rules are
# untouched, so both deployments can talk to the database during the cutover.
resource "aws_vpc_security_group_ingress_rule" "retool_db_from_eks_nodes" {
  count = var.retool_db.security_group_id != null ? 1 : 0

  security_group_id            = var.retool_db.security_group_id
  description                  = "Postgres from ${local.cluster_name} EKS nodes"
  referenced_security_group_id = module.eks.outputs.node_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = data.aws_db_instance.retool.port
  to_port                      = data.aws_db_instance.retool.port
}

# Same for the Temporal database, when there is one.
resource "aws_vpc_security_group_ingress_rule" "temporal_db_from_eks_nodes" {
  count = local.temporal_enabled && var.temporal_db.security_group_id != null ? 1 : 0

  security_group_id            = var.temporal_db.security_group_id
  description                  = "Postgres from ${local.cluster_name} EKS nodes (Temporal)"
  referenced_security_group_id = module.eks.outputs.node_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = var.temporal_db.port
  to_port                      = var.temporal_db.port
}
