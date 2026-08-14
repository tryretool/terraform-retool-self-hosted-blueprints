# Security group rules on the imported database security groups.
#
# The aws-database module is told not to manage rules on these groups
# (manage_security_group_rules = false), because it would delete every rule it
# didn't know about — including the ones the running ECS deployment relies on to
# reach the database. Instead every existing rule is declared here, keyed by its
# AWS rule ID (sgr-...), and imported by import_from_cloudformation.py.
#
# These use aws_vpc_security_group_{ingress,egress}_rule rather than the older
# aws_security_group_rule: one AWS rule per Terraform resource, imported by the
# rule's own ID, with no composite-ID guesswork.
#
# Decommissioning the CloudFormation deployment later is then a matter of
# deleting entries from imported.tfvars — Terraform removes exactly those rules.

locals {
  # Rules are keyed by sgr- ID across two variables per database. Flattening them
  # into one map per direction keeps the resource blocks below to one each.
  preserved_ingress_rules = merge(
    { for id, r in var.retool_db_preserved_ingress_rules : id => merge(r, {
      security_group_id = module.db-main.security_group_id
    }) },
    { for id, r in var.temporal_db_preserved_ingress_rules : id => merge(r, {
      security_group_id = one(module.db-temporal[*].security_group_id)
    }) },
  )

  preserved_egress_rules = merge(
    { for id, r in var.retool_db_preserved_egress_rules : id => merge(r, {
      security_group_id = module.db-main.security_group_id
    }) },
    { for id, r in var.temporal_db_preserved_egress_rules : id => merge(r, {
      security_group_id = one(module.db-temporal[*].security_group_id)
    }) },
  )
}

resource "aws_vpc_security_group_ingress_rule" "preserved" {
  for_each = local.preserved_ingress_rules

  security_group_id            = each.value.security_group_id
  ip_protocol                  = each.value.ip_protocol
  from_port                    = each.value.from_port
  to_port                      = each.value.to_port
  cidr_ipv4                    = each.value.cidr_ipv4
  cidr_ipv6                    = each.value.cidr_ipv6
  referenced_security_group_id = each.value.referenced_security_group_id
  prefix_list_id               = each.value.prefix_list_id
  description                  = each.value.description
}

resource "aws_vpc_security_group_egress_rule" "preserved" {
  for_each = local.preserved_egress_rules

  security_group_id            = each.value.security_group_id
  ip_protocol                  = each.value.ip_protocol
  from_port                    = each.value.from_port
  to_port                      = each.value.to_port
  cidr_ipv4                    = each.value.cidr_ipv4
  cidr_ipv6                    = each.value.cidr_ipv6
  referenced_security_group_id = each.value.referenced_security_group_id
  prefix_list_id               = each.value.prefix_list_id
  description                  = each.value.description
}

# Access for the new deployment. This is the rule aws-database would normally
# add itself; it lives here because rule management on these groups is off.
resource "aws_vpc_security_group_ingress_rule" "retool_db_from_eks_nodes" {
  security_group_id            = module.db-main.security_group_id
  description                  = "Postgres from ${local.cluster_name} EKS nodes"
  referenced_security_group_id = module.eks.outputs.node_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = var.retool_db.port
  to_port                      = var.retool_db.port
}

resource "aws_vpc_security_group_ingress_rule" "temporal_db_from_eks_nodes" {
  count = var.temporal_db_mode == "imported" ? 1 : 0

  security_group_id            = module.db-temporal[0].security_group_id
  description                  = "Postgres from ${local.cluster_name} EKS nodes (Temporal)"
  referenced_security_group_id = module.eks.outputs.node_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = var.temporal_db.port
  to_port                      = var.temporal_db.port
}

# When the Temporal database stays outside Terraform (an Aurora cluster, say),
# its security group still needs to admit the new EKS nodes.
resource "aws_vpc_security_group_ingress_rule" "temporal_db_external_from_eks_nodes" {
  count = var.temporal_db_mode == "external" && try(var.temporal_db_external.security_group_id, null) != null ? 1 : 0

  security_group_id            = var.temporal_db_external.security_group_id
  description                  = "Postgres from ${local.cluster_name} EKS nodes (Temporal)"
  referenced_security_group_id = module.eks.outputs.node_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = var.temporal_db_external.port
  to_port                      = var.temporal_db_external.port
}
