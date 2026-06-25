# from v0.3.0
moved {
  from = module.alb_controller_irsa_role
  to   = module.alb_controller_irsa_role[0]
}

# from v0.3.0
moved {
  from = aws_iam_policy.alb_controller_policy
  to   = aws_iam_policy.alb_controller_policy[0]
}

# from v0.3.0
moved {
  from = aws_iam_role_policy_attachment.alb_controller_policy_attachment
  to   = aws_iam_role_policy_attachment.alb_controller_policy_attachment[0]
}

# from v0.3.0
moved {
  from = helm_release.alb_controller
  to   = helm_release.alb_controller[0]
}

# from v0.3.0
moved {
  from = helm_release.cert_manager
  to   = helm_release.cert_manager[0]
}

# from v0.3.0
moved {
  from = aws_eks_pod_identity_association.eso
  to   = aws_eks_pod_identity_association.eso[0]
}

# from v0.3.0
moved {
  from = helm_release.external_secrets
  to   = helm_release.external_secrets[0]
}

# from v0.3.0
moved {
  from = helm_release.reloader
  to   = helm_release.reloader[0]
}

# from v0.3.0
moved {
  from = kubectl_manifest.external_secret_extra_env_vars
  to   = kubectl_manifest.external_secret_extra_env_vars[0]
}
