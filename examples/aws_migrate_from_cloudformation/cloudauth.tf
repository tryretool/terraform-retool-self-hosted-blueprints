# CloudAuth private integration (Amazon-internal).
#
# Ports the CloudFormation stack's CloudAuth resources: a PrivateLink interface
# endpoint, a private hosted zone that resolves the CloudAuth subdomain to it, an
# IAM policy allowing the application to invoke the CloudAuth API Gateway
# endpoints, and the environment variables the application reads.
#
# Nothing here applies to a standard Retool install — leave var.cloudauth null.

locals {
  cloudauth_enabled = var.cloudauth != null

  # The Retool pods' Kubernetes service account. Named explicitly (rather than
  # left to the chart's fullname template) so the Pod Identity association below
  # can reference it before the Helm release exists.
  retool_service_account_name = "retool"

  cloudauth_iam_enabled = local.cloudauth_enabled && length(var.cloudauth.api_gateway_account_ids) > 0

  cloudauth_values = local.cloudauth_enabled ? [yamlencode({
    serviceAccount = {
      create = true
      name   = local.retool_service_account_name
    }
    env = {
      DEPENDENCIES = jsonencode({
        CloudAuth = {
          fqen = var.cloudauth.fqen
        }
      })
      CloudAuthFQEN = var.cloudauth.fqen
    }
  })] : []
}

# Only the Retool pods call CloudAuth, so the endpoint admits HTTPS from the EKS
# node security group. (The CloudFormation stack allowed it from the load
# balancer security group, which its ECS tasks also ran under.)
resource "aws_security_group" "cloudauth" {
  count = local.cloudauth_enabled ? 1 : 0

  name        = "${var.prefix}-cloudauth"
  description = "CloudAuth PrivateLink endpoint for ${var.prefix}"
  vpc_id      = local.vpc.vpc_id
  tags        = var.tags

  ingress {
    description     = "HTTPS from Retool pods"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [module.eks.outputs.node_security_group_id]
  }
}

resource "aws_vpc_endpoint" "cloudauth" {
  count = local.cloudauth_enabled ? 1 : 0

  vpc_id             = local.vpc.vpc_id
  service_name       = var.cloudauth.vpc_endpoint_service_name
  vpc_endpoint_type  = "Interface"
  subnet_ids         = local.vpc.private_subnet_ids
  security_group_ids = [aws_security_group.cloudauth[0].id]
  tags               = var.tags
}

# A private zone for the CloudAuth subdomain, resolvable only inside this VPC,
# aliasing to the interface endpoint.
resource "aws_route53_zone" "cloudauth" {
  count = local.cloudauth_enabled ? 1 : 0

  name    = var.cloudauth.subdomain
  comment = "CloudAuth private DNS for ${var.prefix}"
  tags    = var.tags

  vpc {
    vpc_id = local.vpc.vpc_id
  }
}

resource "aws_route53_record" "cloudauth" {
  count = local.cloudauth_enabled ? 1 : 0

  zone_id = aws_route53_zone.cloudauth[0].zone_id
  name    = var.cloudauth.subdomain
  type    = "A"

  alias {
    name                   = aws_vpc_endpoint.cloudauth[0].dns_entry[0].dns_name
    zone_id                = aws_vpc_endpoint.cloudauth[0].dns_entry[0].hosted_zone_id
    evaluate_target_health = true
  }
}

# The blueprints give the Retool pods no AWS identity of their own, so calling
# CloudAuth's API Gateway endpoints needs a role plus an EKS Pod Identity
# association binding it to the Retool service account.
resource "aws_iam_policy" "cloudauth_invoke" {
  count = local.cloudauth_iam_enabled ? 1 : 0

  name        = "${var.prefix}-cloudauth-invoke"
  description = "Allows Retool to invoke the CloudAuth API Gateway endpoints"
  tags        = var.tags

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "execute-api:Invoke"
      Resource = [for id in var.cloudauth.api_gateway_account_ids : "arn:aws:execute-api:*:${id}:*"]
    }]
  })
}

resource "aws_iam_role" "retool" {
  count = local.cloudauth_iam_enabled ? 1 : 0

  name = "${var.prefix}-retool"
  tags = var.tags

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })
}

resource "aws_iam_role_policy_attachment" "retool_cloudauth_invoke" {
  count = local.cloudauth_iam_enabled ? 1 : 0

  role       = aws_iam_role.retool[0].name
  policy_arn = aws_iam_policy.cloudauth_invoke[0].arn
}

resource "aws_eks_pod_identity_association" "retool" {
  count = local.cloudauth_iam_enabled ? 1 : 0

  cluster_name    = module.eks.outputs.name
  namespace       = "default"
  service_account = local.retool_service_account_name
  role_arn        = aws_iam_role.retool[0].arn
}
