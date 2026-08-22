locals {
  external_secrets = {
    name                 = "external-secrets"
    namespace            = "external-secrets"
    service_account_name = "external-secrets"
    role_name            = "${local.cluster_name}-external-secrets"
  }

  # Per-deployment roles this controller may assume. Each aws-retool-services
  # instance creates a "<prefix>-eso" role holding read access to just its own
  # secrets, and names this controller in that role's trust policy; the
  # deployment's SecretStore then selects it via spec.provider.aws.role. Granting
  # by name pattern keeps this module from having to know the deployments.
  external_secrets_assumable_role_arns = coalesce(
    var.external_secrets_assumable_role_arns,
    ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/*-eso"],
  )
}

# The controller holds no secret-reading permissions of its own — it only ever
# assumes a per-deployment role, so one Retool deployment's ExternalSecrets can
# never reach another's secrets.
resource "aws_iam_role" "external_secrets" {
  count = var.enable_external_secrets ? 1 : 0

  name = local.external_secrets.role_name
  tags = local.all_tags

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })
}

# Same-account assumption is already satisfied by the per-deployment role's trust
# policy; this identity-side grant is belt and braces for accounts with SCPs or
# permission boundaries that require both.
resource "aws_iam_policy" "external_secrets" {
  count = var.enable_external_secrets ? 1 : 0

  name        = local.external_secrets.role_name
  description = "Allows the cluster External Secrets Operator to assume per-deployment Retool ESO roles"
  tags        = local.all_tags

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "sts:AssumeRole"
      Resource = local.external_secrets_assumable_role_arns
    }]
  })
}

resource "aws_iam_role_policy_attachment" "external_secrets" {
  count = var.enable_external_secrets ? 1 : 0

  role       = aws_iam_role.external_secrets[0].name
  policy_arn = aws_iam_policy.external_secrets[0].arn
}

resource "aws_eks_pod_identity_association" "external_secrets" {
  count = var.enable_external_secrets ? 1 : 0

  cluster_name    = local.cluster.name
  namespace       = local.external_secrets.namespace
  service_account = local.external_secrets.service_account_name
  role_arn        = aws_iam_role.external_secrets[0].arn

  # In create mode the agent is one of module.eks's addons; when adopting a
  # cluster it is the standalone resource.
  depends_on = [
    module.eks,
    aws_eks_addon.pod_identity_agent,
  ]
}

# A cluster-wide singleton: its CRDs and its ValidatingWebhookConfigurations have
# fixed cluster-scoped names, so a second release cannot coexist. Each Retool
# deployment gets its own namespaced SecretStore reconciled by this controller.
resource "helm_release" "external_secrets" {
  count = var.enable_external_secrets ? 1 : 0

  namespace        = local.external_secrets.namespace
  create_namespace = true

  name       = local.external_secrets.name
  repository = "https://charts.external-secrets.io"
  chart      = "external-secrets"
  version    = "2.8.0"
  wait       = true

  values = [
    yamlencode({
      installCRDs    = var.install_crds
      serviceAccount = { name = local.external_secrets.service_account_name }
      crds           = { unsafeServeV1Beta1 = var.external_secrets_serve_v1beta1 }
    }),
    yamlencode(local.has_pod_scheduling ? merge(local.pod_scheduling, {
      webhook        = local.pod_scheduling
      certController = local.pod_scheduling
    }) : {}),
  ]

  depends_on = [module.eks]
}
