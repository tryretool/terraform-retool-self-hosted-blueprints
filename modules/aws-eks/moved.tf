# from v0.3.0
moved {
  from = module.karpenter
  to   = module.karpenter[0]
}

# from v0.3.0
moved {
  from = aws_iam_instance_profile.karpenter
  to   = aws_iam_instance_profile.karpenter[0]
}

# from v0.3.0
moved {
  from = helm_release.karpenter_crd
  to   = helm_release.karpenter_crd[0]
}

# from v0.3.0
moved {
  from = helm_release.karpenter
  to   = helm_release.karpenter[0]
}

# from v0.3.0
moved {
  from = kubectl_manifest.karpenter_ec2nodeclass_default
  to   = kubectl_manifest.karpenter_ec2nodeclass_default[0]
}

# from v0.3.0
moved {
  from = kubectl_manifest.karpenter_nodepool_default
  to   = kubectl_manifest.karpenter_nodepool_default[0]
}

# The cluster and its KMS key are now counted so this module can adopt a
# pre-existing cluster instead of creating one (var.existing_cluster).
moved {
  from = module.eks
  to   = module.eks[0]
}

moved {
  from = aws_kms_key.eks
  to   = aws_kms_key.eks[0]
}
