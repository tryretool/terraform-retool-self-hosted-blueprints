# Everything this module exports, enumerated explicitly. local.cluster resolves
# each cluster attribute from either the cluster we created or the one we
# adopted (see existing-cluster.tf); the rest are this module's own resources.
locals {
  outputs = {
    arn                        = local.cluster.arn
    certificate_authority_data = local.cluster.certificate_authority_data
    endpoint                   = local.cluster.endpoint
    name                       = local.cluster.name
    platform_version           = local.cluster.platform_version
    status                     = local.cluster.status
    oidc_issuer_url            = local.cluster.oidc_issuer_url
    oidc_provider_arn          = local.cluster.oidc_provider_arn
    oidc_provider              = local.cluster.oidc_provider

    cluster_security_group_id = local.cluster.cluster_security_group_id
    node_security_group_id    = local.cluster.node_security_group_id

    node_groups = local.cluster.node_groups

    vpc_id = local.vpc_id

    # Identity of the cluster's shared External Secrets Operator. Each
    # aws-retool-services instance names this principal in the trust policy of
    # its own <prefix>-eso role, which its SecretStore then selects via
    # spec.provider.aws.role.
    eso_controller_role_arn  = one(aws_iam_role.external_secrets[*].arn)
    eso_controller_role_name = one(aws_iam_role.external_secrets[*].name)

    alb_controller_role_arn  = one(module.alb_controller_role[*].iam_role_arn)
    alb_controller_role_name = one(module.alb_controller_role[*].iam_role_name)
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
    instance_profile = var.enable_karpenter ? {
      id   = aws_iam_instance_profile.karpenter[0].id
      arn  = aws_iam_instance_profile.karpenter[0].arn
      name = local.karpenter.instance_profile_name
    } : null
    discovery_key   = local.karpenter.discovery_key
    discovery_value = local.karpenter.discovery_value
  }
}

output "vpc_id" {
  value       = local.outputs.vpc_id
  description = "ID of the VPC the cluster runs in — as supplied via vpc, or read from the live cluster when adopting one."
}

output "eso_controller_role_arn" {
  value       = local.outputs.eso_controller_role_arn
  description = "ARN of the IAM role used by the cluster's External Secrets Operator. Per-deployment aws-retool-services modules trust this principal so it can assume their own <prefix>-eso role. Null when enable_external_secrets is false."
}

output "alb_controller_role_arn" {
  value       = local.outputs.alb_controller_role_arn
  description = "ARN of the IAM role used by the AWS Load Balancer Controller. Null when enable_alb_controller is false."
}

output "alb_controller_role_name" {
  value       = local.outputs.alb_controller_role_name
  description = "Name of the IAM role used by the AWS Load Balancer Controller. Null when enable_alb_controller is false."
}
