locals {
  eso = {
    name                 = "external-secrets"
    namespace            = "external-secrets"
    service_account_name = "external-secrets"
  }

  retool_namespace       = "default"
  encryption_key_sm_path = "retool/${var.prefix}/encryption-key"

  # Secrets Manager path/ARN for the license key, sourced from either the managed
  # secret (var.license_key) or an existing one (var.license_key_secret_path).
  # null when neither is set (free-tier mode).
  license_key_remote_ref = (
    nonsensitive(var.license_key != null)
    ? "retool/${var.prefix}/license-key"
    : var.license_key_secret_path
  )

  external_secrets = concat(
    [
      {
        name = "encryption-key"
        data = [{
          secretKey = "encryption-key"
          remoteRef = {
            key = var.encryption_key_secret_name != null ? var.encryption_key_secret_name : local.encryption_key_sm_path
          }
        }]
        target_deletion_policy = "Retain"
      },
      {
        name = "jwt-secret"
        data = [{
          secretKey = "jwt-secret"
          remoteRef = { key = "retool/${var.prefix}/jwt-secret" }
        }]
        target_deletion_policy = "Retain"
      },
      {
        name = "db-credentials"
        data = [{
          secretKey = "password"
          remoteRef = {
            key      = var.db.master_user_secret_arn
            property = "password"
          }
        }]
        target_deletion_policy = "Retain"
      },
    ],
    local.license_key_remote_ref != null ? [
      {
        name = "license-key"
        data = [{
          secretKey = "license-key"
          remoteRef = { key = local.license_key_remote_ref }
        }]
        target_deletion_policy = "Retain"
      },
    ] : [],
  )

  agent_sandbox_external_secret = var.enable_agent_sandbox ? {
    name   = "agent-sandbox"
    sm_key = "retool/${var.prefix}/agent-sandbox"
  } : null
}

data "aws_caller_identity" "current" {}

resource "aws_iam_role" "eso" {
  name = "${var.prefix}-eso"
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

resource "aws_iam_policy" "eso" {
  name        = "${var.prefix}-eso"
  description = "Allows External Secrets Operator to read Retool secrets from AWS Secrets Manager"
  tags        = local.all_tags

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [{
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret",
          "secretsmanager:ListSecretVersionIds",
          "secretsmanager:GetResourcePolicy",
          "secretsmanager:BatchGetSecretValue",
        ]
        Resource = "arn:aws:secretsmanager:${var.region}:${data.aws_caller_identity.current.account_id}:secret:retool/${var.prefix}/*"
      }],
      [{
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret",
          "secretsmanager:ListSecretVersionIds",
          "secretsmanager:GetResourcePolicy",
          "secretsmanager:BatchGetSecretValue",
        ]
        Resource = var.db.master_user_secret_arn
      }],
      var.encryption_key_secret_name != null ? [{
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret",
          "secretsmanager:ListSecretVersionIds",
          "secretsmanager:GetResourcePolicy",
          "secretsmanager:BatchGetSecretValue",
        ]
        Resource = var.encryption_key_secret_name
      }] : [],
      var.license_key_secret_path != null ? [{
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret",
          "secretsmanager:ListSecretVersionIds",
          "secretsmanager:GetResourcePolicy",
          "secretsmanager:BatchGetSecretValue",
        ]
        Resource = var.license_key_secret_path
      }] : []
    )
  })
}

resource "aws_iam_role_policy_attachment" "eso" {
  role       = aws_iam_role.eso.name
  policy_arn = aws_iam_policy.eso.arn
}

resource "aws_eks_pod_identity_association" "eso" {
  cluster_name    = var.eks.name
  namespace       = local.eso.namespace
  service_account = local.eso.service_account_name
  role_arn        = aws_iam_role.eso.arn
}

resource "helm_release" "external_secrets" {
  namespace        = local.eso.namespace
  create_namespace = true

  name       = local.eso.name
  repository = "https://charts.external-secrets.io"
  chart      = "external-secrets"
  version    = "0.12.1"
  wait       = true

  values = [yamlencode({
    installCRDs = true
  })]
}

resource "kubectl_manifest" "secret_store" {
  yaml_body = yamlencode({
    apiVersion = "external-secrets.io/v1beta1"
    kind       = "ClusterSecretStore"
    metadata = {
      name = "aws-secretsmanager"
    }
    spec = {
      provider = {
        aws = {
          service = "SecretsManager"
          region  = var.region
        }
      }
    }
  })

  depends_on = [helm_release.external_secrets]
}

resource "kubectl_manifest" "external_secret" {
  for_each = { for s in local.external_secrets : s.name => s }

  yaml_body = yamlencode({
    apiVersion = "external-secrets.io/v1beta1"
    kind       = "ExternalSecret"
    metadata = {
      name      = each.value.name
      namespace = local.retool_namespace
    }
    spec = {
      refreshInterval = "1m"
      secretStoreRef = {
        kind = "ClusterSecretStore"
        name = "aws-secretsmanager"
      }
      target = {
        name           = each.value.name
        creationPolicy = "Owner"
        deletionPolicy = each.value.target_deletion_policy
      }
      data = each.value.data
    }
  })

  depends_on = [kubectl_manifest.secret_store]
}

resource "kubectl_manifest" "external_secret_agent_sandbox" {
  count = var.enable_agent_sandbox ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "external-secrets.io/v1beta1"
    kind       = "ExternalSecret"
    metadata = {
      name      = local.agent_sandbox_external_secret.name
      namespace = local.retool_namespace
    }
    spec = {
      refreshInterval = "1m"
      secretStoreRef = {
        kind = "ClusterSecretStore"
        name = "aws-secretsmanager"
      }
      target = {
        name           = local.agent_sandbox_external_secret.name
        creationPolicy = "Owner"
        deletionPolicy = "Retain"
      }
      dataFrom = [{
        extract = {
          key = local.agent_sandbox_external_secret.sm_key
        }
      }]
    }
  })

  depends_on = [kubectl_manifest.secret_store]
}

resource "kubectl_manifest" "external_secret_extra_env_vars" {
  yaml_body = yamlencode({
    apiVersion = "external-secrets.io/v1beta1"
    kind       = "ExternalSecret"
    metadata = {
      name      = "extra-env-vars"
      namespace = local.retool_namespace
    }
    spec = {
      refreshInterval = "1m"
      secretStoreRef = {
        kind = "ClusterSecretStore"
        name = "aws-secretsmanager"
      }
      target = {
        name           = "extra-env-vars"
        creationPolicy = "Owner"
        deletionPolicy = "Merge"
      }
      dataFrom = [{
        extract = {
          key = "retool/${var.prefix}/extra-env-vars"
        }
      }]
    }
  })

  depends_on = [kubectl_manifest.secret_store]
}
