data "aws_availability_zones" "available" {}

locals {
  # Use first 3 AZs
  azs      = slice(data.aws_availability_zones.available.names, 0, 3)
  all_tags = merge(var.default_tags, var.tags)
  
  private_subnet_tags = merge(var.private_subnet_tags, {
    # In the aws/retool-services module, the `karpenter.sh/discovery` tag value
    # must match the EKS cluster name.
    "karpenter.sh/discovery"          = substr(var.prefix, 0, 38)
    # Discovery tag for ALB controller, see https://kubernetes-sigs.github.io/aws-load-balancer-controller/v2.6/deploy/subnet_discovery/
    "kubernetes.io/role/internal-elb" = "1"
  })
  public_subnet_tags = merge(var.public_subnet_tags, {
    # Discovery tag for ALB controller, see https://kubernetes-sigs.github.io/aws-load-balancer-controller/v2.6/deploy/subnet_discovery/
    "kubernetes.io/role/elb" = "1"
  })
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "6.6.0"
  name    = "${var.prefix}-vpc"
  cidr    = var.cidr_block
  azs     = local.azs

  public_subnet_suffix = "pub"
  public_subnets       = var.public_subnets
  public_subnet_names  = [for az in local.azs : "${var.prefix}-pub-${az}-subnet"]

  private_subnet_suffix = "app"
  private_subnets       = var.private_subnets
  private_subnet_names  = [for az in local.azs : "${var.prefix}-app-${az}-subnet"]

  default_network_acl_ingress = var.default_network_acl_ingress_rules
  default_network_acl_egress  = var.default_network_acl_egress_rules

  enable_flow_log                                 = var.enable_flow_logs
  flow_log_destination_type                       = "cloud-watch-logs"
  create_flow_log_cloudwatch_log_group            = var.enable_flow_logs
  create_flow_log_cloudwatch_iam_role             = var.enable_flow_logs
  flow_log_cloudwatch_log_group_name_prefix       = "${var.prefix}-vpc-flow-logs"
  flow_log_cloudwatch_log_group_retention_in_days = var.flow_log_retention_days
  flow_log_traffic_type                           = "ALL"

  enable_nat_gateway            = true
  one_nat_gateway_per_az        = true
  enable_vpn_gateway            = false
  manage_default_network_acl    = true
  manage_default_security_group = true
  enable_dns_hostnames          = true

  tags                = local.all_tags
  private_subnet_tags = local.private_subnet_tags
  public_subnet_tags  = local.public_subnet_tags
  igw_tags = {
    Name = "${var.prefix}-vpc-igw"
  }
  public_route_table_tags = {
    Name = "${var.prefix}-vpc-public-rt"
  }
}
