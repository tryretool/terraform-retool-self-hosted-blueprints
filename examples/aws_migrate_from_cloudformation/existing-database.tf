# Adopts the Retool RDS instance your CloudFormation stack already runs, instead
# of creating one with the aws-database module.
#
# This is the whole point of the migration: the instance holds every app, query,
# resource and user in your deployment, and it is neither recreated nor modified
# here. Terraform only reads its connection details and opens a path to it from
# the new EKS nodes.

data "aws_db_instance" "retool" {
  db_instance_identifier = var.db.instance_identifier
}

locals {
  # Same shape as module.db-main.outputs in the all-inclusive examples.
  #
  # master_user_secret_arn names the secret External Secrets Operator reads the
  # password from. For an RDS-managed master user that would be the secret RDS
  # rotates; here it is the secret CloudFormation generated, whose
  # {"username": ..., "password": ...} shape ESO reads the same way.
  db = {
    address                = data.aws_db_instance.retool.address
    port                   = data.aws_db_instance.retool.port
    name                   = data.aws_db_instance.retool.db_name
    username               = data.aws_db_instance.retool.master_username
    master_user_secret_arn = var.db.credentials_secret_id
  }
}

# The CloudFormation stack's RDS security group only admits its own ECS tasks.
# Retool pods reach Postgres from the EKS node security group, so it needs a
# rule of its own. This is additive — the existing ECS ingress rules are
# untouched, so both deployments can talk to the database during the cutover.
resource "aws_vpc_security_group_ingress_rule" "retool_db_from_eks_nodes" {
  count = var.db.security_group_id != null ? 1 : 0

  security_group_id            = var.db.security_group_id
  description                  = "Postgres from ${local.cluster_name} EKS nodes"
  referenced_security_group_id = module.eks.outputs.node_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = data.aws_db_instance.retool.port
  to_port                      = data.aws_db_instance.retool.port
}
