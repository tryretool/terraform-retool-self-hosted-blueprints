# EBS CSI driver — required for persistent volume support (e.g. StatefulSets,
# Grafana). Deployed as a managed EKS addon with a dedicated IRSA
# role so the controller pods can provision/attach EBS volumes.

module "ebs_csi_irsa" {
  count   = var.enable_ebs_csi_driver ? 1 : 0
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "5.60.0"

  role_name             = "${local.cluster_name}-ebs-csi"
  attach_ebs_csi_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }

  tags = local.all_tags
}

resource "aws_eks_addon" "ebs_csi" {
  count = var.enable_ebs_csi_driver ? 1 : 0

  cluster_name                = module.eks.cluster_name
  addon_name                  = "aws-ebs-csi-driver"
  resolve_conflicts_on_create = "OVERWRITE"
  service_account_role_arn    = module.ebs_csi_irsa[0].iam_role_arn

  configuration_values = jsonencode({
    controller = {
      tolerations = [
        {
          key    = "karpenter.sh/controller"
          value  = "true"
          effect = "NoSchedule"
        },
        {
          key    = "CriticalAddonsOnly"
          value  = "true"
          effect = "NoSchedule"
        },
      ]
    }
  })

  depends_on = [module.eks]
}
