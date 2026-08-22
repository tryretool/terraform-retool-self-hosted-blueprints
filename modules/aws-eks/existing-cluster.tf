# Adopting a pre-existing cluster.
#
# When var.existing_cluster is set this module creates no cluster, KMS key or
# node group, and instead resolves the same attributes from the live cluster so
# everything downstream — the addons, the cluster-singleton Helm charts, and the
# module's own outputs — works identically in both modes.
#
# Every reference to the cluster elsewhere in this module goes through
# local.cluster rather than module.eks directly, so neither branch is ever
# indexed when it has zero instances.

data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

data "aws_region" "current" {}

data "aws_eks_cluster" "existing" {
  count = local.byo_cluster ? 1 : 0

  name = var.existing_cluster.name
}

# EKS does not create an IAM OIDC provider on its own — terraform-aws-modules/eks
# does. A cluster we did not create may not have one, so only look it up when the
# caller did not hand us the ARN directly.
data "aws_iam_openid_connect_provider" "existing" {
  count = local.byo_cluster && var.existing_cluster.oidc_provider_arn == null ? 1 : 0

  url = data.aws_eks_cluster.existing[0].identity[0].oidc[0].issuer
}

locals {
  cluster_from_created = [for m in module.eks : {
    arn                        = m.cluster_arn
    certificate_authority_data = m.cluster_certificate_authority_data
    endpoint                   = m.cluster_endpoint
    name                       = m.cluster_name
    platform_version           = m.cluster_platform_version
    status                     = m.cluster_status
    oidc_issuer_url            = m.cluster_oidc_issuer_url
    oidc_provider_arn          = m.oidc_provider_arn
    oidc_provider              = m.oidc_provider
    cluster_security_group_id  = m.cluster_security_group_id
    node_security_group_id     = m.node_security_group_id
    node_groups                = m.eks_managed_node_groups
  }]

  cluster_from_existing = [for d in data.aws_eks_cluster.existing : {
    arn                        = d.arn
    certificate_authority_data = d.certificate_authority[0].data
    endpoint                   = d.endpoint
    name                       = d.name
    platform_version           = d.platform_version
    status                     = d.status
    oidc_issuer_url            = d.identity[0].oidc[0].issuer
    oidc_provider_arn = coalesce(
      var.existing_cluster.oidc_provider_arn,
      one(data.aws_iam_openid_connect_provider.existing[*].arn),
    )
    oidc_provider             = replace(d.identity[0].oidc[0].issuer, "https://", "")
    cluster_security_group_id = d.vpc_config[0].cluster_security_group_id
    # Not discoverable from the cluster API — the caller supplies it, and the
    # database and user-ingress modules need it to allow traffic from the nodes.
    node_security_group_id = var.existing_cluster.node_security_group_id
    node_groups            = {}
  }]

  cluster = one(concat(local.cluster_from_created, local.cluster_from_existing))

  # The VPC as supplied, or the adopted cluster's own.
  vpc_id = coalesce(
    try(var.vpc.vpc_id, null),
    one([for d in data.aws_eks_cluster.existing : d.vpc_config[0].vpc_id]),
  )
}

# In create mode the pod identity agent is one of the addons declared on
# module.eks. Adopted clusters need it installed separately, otherwise the pod
# identity associations below are accepted by the API but no pod ever receives
# credentials.
resource "aws_eks_addon" "pod_identity_agent" {
  count = local.byo_cluster && var.enable_pod_identity_agent ? 1 : 0

  cluster_name                = local.cluster.name
  addon_name                  = "eks-pod-identity-agent"
  resolve_conflicts_on_create = "OVERWRITE"
}
