# Adopts the VPC your CloudFormation stack already runs in, instead of creating
# one with the aws-vpc module.
#
# Downstream modules take a `vpc` object rather than a module reference, so all
# that's needed is to assemble the same shape from data sources — plus the two
# subnet tags the aws-vpc module would otherwise have applied.

data "aws_vpc" "existing" {
  id = var.vpc_id
}

locals {
  # Same shape as module.vpc.outputs in the all-inclusive examples.
  vpc = {
    vpc_id             = data.aws_vpc.existing.id
    vpc_cidr_block     = data.aws_vpc.existing.cidr_block
    private_subnet_ids = var.private_subnet_ids
    public_subnet_ids  = var.public_subnet_ids
  }

  # The aws-eks module truncates the prefix to 38 characters for the cluster
  # name, and Karpenter's discovery tag value must equal that cluster name.
  cluster_name = substr(var.prefix, 0, 38)

  load_balancer_subnet_tags = var.tag_subnets_for_load_balancer_discovery ? merge(
    { for id in var.public_subnet_ids : "${id}:kubernetes.io/role/elb" => {
      subnet_id = id
      key       = "kubernetes.io/role/elb"
    } },
    { for id in var.private_subnet_ids : "${id}:kubernetes.io/role/internal-elb" => {
      subnet_id = id
      key       = "kubernetes.io/role/internal-elb"
    } },
  ) : {}
}

# Karpenter's EC2NodeClass selects subnets by this tag (see
# modules/aws-eks/karpenter.tf). Without it, Karpenter finds nowhere to launch
# nodes and every workload pod stays Pending.
resource "aws_ec2_tag" "karpenter_discovery" {
  for_each = var.manage_karpenter_subnet_tags ? toset(var.private_subnet_ids) : toset([])

  resource_id = each.value
  key         = "karpenter.sh/discovery"
  value       = local.cluster_name
}

# Optional: lets the AWS Load Balancer Controller auto-discover subnets for any
# Ingress you create later. The user ALB in this stack names its subnets
# explicitly, so this is not required for Retool itself.
resource "aws_ec2_tag" "load_balancer_role" {
  for_each = local.load_balancer_subnet_tags

  resource_id = each.value.subnet_id
  key         = each.value.key
  value       = "1"
}
