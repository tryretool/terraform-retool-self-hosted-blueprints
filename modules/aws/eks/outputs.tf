locals {
  outputs = {
    arn                        = module.eks.cluster_arn
    certificate_authority_data = module.eks.cluster_certificate_authority_data
    endpoint                   = module.eks.cluster_endpoint
    name                       = module.eks.cluster_name
    platform_version           = module.eks.cluster_platform_version
    status                     = module.eks.cluster_status
    oidc_issuer_url            = module.eks.cluster_oidc_issuer_url
    oidc_provider_arn          = module.eks.oidc_provider_arn
    oidc_provider              = module.eks.oidc_provider

    cluster_security_group_id = module.eks.cluster_security_group_id
    node_security_group_id    = module.eks.node_security_group_id

    node_groups = module.eks.eks_managed_node_groups
  }
}

output "cluster" {
  // NOTE: these are declared here -
  // https://registry.terraform.io/modules/terraform-aws-modules/eks/aws/latest?tab=outputs
  value       = local.outputs
  description = "A map of EKS cluster attributes: arn, certificate_authority_data, endpoint, name, platform_version, status, oidc_issuer_url, oidc_provider_arn, cluster_security_group_id, node_security_group_id."
}

output "outputs" {
  value       = local.outputs
  description = "Structured EKS cluster outputs for composition with downstream modules."
}

output "karpenter" {
  value = {
    instance_profile = {
      id   = resource.aws_iam_instance_profile.karpenter.id
      arn  = resource.aws_iam_instance_profile.karpenter.arn
      name = local.karpenter.instance_profile_name
    }
    discovery_key   = local.karpenter.discovery_key
    discovery_value = local.karpenter.discovery_value
  }
}
