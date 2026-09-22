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
#
# Keyed by security group and port rather than by database: the Retool
# templates put both databases behind a single RDSSecurityGroup, and AWS rejects
# a duplicate rule. One entry per distinct (group, port) pair covers a shared
# group, separate groups, and separate ports alike.
locals {
  # merge() rather than a for-expression: it collapses duplicate keys, whereas a
  # for-expression building a map errors on them.
  db_ingress_rules = merge(
    var.retool_db.security_group_id != null ? {
      "${var.retool_db.security_group_id}:${data.aws_db_instance.retool.port}" = {
        security_group_id = var.retool_db.security_group_id
        port              = data.aws_db_instance.retool.port
      }
    } : {},
    try(var.temporal_db.security_group_id, null) != null ? {
      "${var.temporal_db.security_group_id}:${var.temporal_db.port}" = {
        security_group_id = var.temporal_db.security_group_id
        port              = var.temporal_db.port
      }
    } : {},
  )
}

resource "aws_vpc_security_group_ingress_rule" "db_from_eks_nodes" {
  for_each = local.db_ingress_rules

  security_group_id            = each.value.security_group_id
  description                  = "Postgres from ${local.cluster_name} EKS nodes"
  referenced_security_group_id = module.eks.outputs.node_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = each.value.port
  to_port                      = each.value.port
}
