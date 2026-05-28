locals {
  all_tags = merge(var.default_tags, var.tags)
  alb_controller = {
    name                 = "alb-controller"
    namespace            = "alb-controller"
    service_account_name = "alb-controller"
  }

  # The ALB controller provisions AWS resources (load balancers, target groups,
  # listeners, security groups) via the AWS API at runtime, so the provider's
  # default_tags never reach them — we have to feed them to the controller
  # explicitly via its --default-tags flag. Module-level tags take precedence
  # over provider-level tags on collision.
  alb_controller_default_tags = merge(data.aws_default_tags.current.tags, local.all_tags)
}

data "aws_default_tags" "current" {}

module "alb_controller_irsa_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "5.60.0"

  role_name                              = "${var.prefix}-alb-controller"
  attach_load_balancer_controller_policy = false
  tags                                   = local.all_tags

  oidc_providers = {
    main = {
      provider_arn               = var.eks.oidc_provider_arn
      namespace_service_accounts = ["${local.alb_controller.namespace}:${local.alb_controller.service_account_name}"]
    }
  }
}

resource "aws_iam_policy" "alb_controller_policy" {
  name        = "${var.prefix}-alb-controller"
  description = "IAM policy for the ALB controller (aws-load-balancer-controller chart)"
  path        = "/"
  tags        = local.all_tags

  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Action" : [
          "acm:DescribeCertificate",
          "acm:ListCertificates",
          "acm:GetCertificate",
          "ec2:AuthorizeSecurityGroupIngress",
          "ec2:CreateSecurityGroup",
          "ec2:CreateTags",
          "ec2:DeleteTags",
          "ec2:DeleteSecurityGroup",
          "ec2:DescribeAccountAttributes",
          "ec2:DescribeAddresses",
          "ec2:DescribeAvailabilityZones",
          "ec2:DescribeInternetGateways",
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceStatus",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeSubnets",
          "ec2:DescribeTags",
          "ec2:DescribeVpcs",
          "ec2:ModifyInstanceAttribute",
          "ec2:ModifyNetworkInterfaceAttribute",
          "ec2:RevokeSecurityGroupIngress",
          "elasticloadbalancing:AddListenerCertificates",
          "elasticloadbalancing:AddTags",
          "elasticloadbalancing:CreateListener",
          "elasticloadbalancing:CreateLoadBalancer",
          "elasticloadbalancing:CreateRule",
          "elasticloadbalancing:CreateTargetGroup",
          "elasticloadbalancing:DeleteListener",
          "elasticloadbalancing:DeleteLoadBalancer",
          "elasticloadbalancing:DeleteRule",
          "elasticloadbalancing:DeleteTargetGroup",
          "elasticloadbalancing:DeregisterTargets",
          "elasticloadbalancing:DescribeListenerCertificates",
          "elasticloadbalancing:DescribeListenerAttributes",
          "elasticloadbalancing:DescribeListeners",
          "elasticloadbalancing:DescribeLoadBalancers",
          "elasticloadbalancing:DescribeLoadBalancerAttributes",
          "elasticloadbalancing:DescribeRules",
          "elasticloadbalancing:DescribeSSLPolicies",
          "elasticloadbalancing:DescribeTags",
          "elasticloadbalancing:DescribeTargetGroups",
          "elasticloadbalancing:DescribeTargetGroupAttributes",
          "elasticloadbalancing:DescribeTargetHealth",
          "elasticloadbalancing:ModifyListener",
          "elasticloadbalancing:ModifyListenerAttributes",
          "elasticloadbalancing:ModifyLoadBalancerAttributes",
          "elasticloadbalancing:ModifyRule",
          "elasticloadbalancing:ModifyTargetGroup",
          "elasticloadbalancing:ModifyTargetGroupAttributes",
          "elasticloadbalancing:RegisterTargets",
          "elasticloadbalancing:RemoveListenerCertificates",
          "elasticloadbalancing:RemoveTags",
          "elasticloadbalancing:SetIpAddressType",
          "elasticloadbalancing:SetRulePriorities",
          "elasticloadbalancing:SetSecurityGroups",
          "elasticloadbalancing:SetSubnets",
          "elasticloadbalancing:SetWebAcl",
          "iam:CreateServiceLinkedRole",
          "iam:GetServerCertificate",
          "iam:ListServerCertificates",
          "shield:GetSubscriptionState",
          "shield:DescribeProtection",
          "shield:CreateProtection",
          "shield:DeleteProtection",
          "waf:GetWebACL",
          "waf:AssociateWebACL",
          "waf:DisassociateWebACL",
          "wafv2:GetWebACL",
          "wafv2:GetWebACLForResource",
          "wafv2:AssociateWebACL",
          "wafv2:DisassociateWebACL",
          "tag:GetResources",
          "tag:TagResources",
          "tag:UntagResources",
          "waf-regional:GetWebACL",
          "waf-regional:AssociateWebACL",
          "waf-regional:DisassociateWebACL"
        ],
        "Resource" : "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "alb_controller_policy_attachment" {
  role       = module.alb_controller_irsa_role.iam_role_name
  policy_arn = aws_iam_policy.alb_controller_policy.arn
}

resource "helm_release" "alb_controller" {
  namespace        = local.alb_controller.namespace
  create_namespace = true

  name       = local.alb_controller.name
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = "v1.13.2"

  # values reference: https://github.com/aws/eks-charts/blob/master/stable/aws-load-balancer-controller/values.yaml
  values = [yamlencode({
    nameOverride = local.alb_controller.name
    # set region and vpcId, otherwise it tries to discover these via ec2
    # metadata which hits permissions errors
    region = var.region
    vpcId  = var.vpc.vpc_id
    # without the cert-manager dependency, this chart tries to create its own
    # tls certs dynamically which the helm provider can't deal with
    enableCertManager = true
    clusterName       = var.eks.name
    rbac = {
      create = true
    }
    serviceAccount = {
      create = true
      name   = local.alb_controller.service_account_name
      annotations = {
        "eks.amazonaws.com/role-arn" = module.alb_controller_irsa_role.iam_role_arn
      }
    }
    # make the created IngressClass the cluster default
    ingressClassConfig = {
      default = true
    }
    # propagated to every AWS resource the controller creates (ALBs, target
    # groups, listeners, controller-managed security groups). becomes the
    # --default-tags CLI flag on the controller.
    defaultTags = local.alb_controller_default_tags
  })]

  depends_on = [
    helm_release.cert_manager,
  ]
}
