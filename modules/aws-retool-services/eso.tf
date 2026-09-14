locals {
  # Namespaced SecretStore (lives in the retool namespace alongside the
  # ExternalSecrets that reference it), rather than a cluster-global
  # ClusterSecretStore whose fixed name would collide in a shared cluster.
  secret_store_kind = "SecretStore"
  secret_store_name = "retool-secretstore"

  # The External Secrets Operator runs once per cluster and is not deployed by
  # this module. Whichever controller reconciles this deployment's SecretStore
  # assumes the role below to read the secrets; it is named here so the role
  # will trust it.
  eso_trusted_principals = distinct(compact(concat(
    [try(var.eks.eso_controller_role_arn, null)],
    var.eso_controller_role_arns,
  )))

  encryption_key_sm_path = "retool/${var.prefix}/encryption-key"

  # Secrets Manager path/ARN for the license key, sourced from either the managed
  # secret (var.license_key) or an existing one (var.license_key_secret_path).
  # null when neither is set (free-tier mode).
  license_key_remote_ref = (
    nonsensitive(var.license_key != null)
    ? "retool/${var.prefix}/license-key"
    : var.license_key_secret_path
  )

  jwt_secret_remote_ref = coalesce(var.jwt_secret_secret_path, "retool/${var.prefix}/jwt-secret")

  external_secrets = concat(
    [
      {
        name = "encryption-key"
        data = [{
          secretKey = "encryption-key"
          remoteRef = merge(
            {
              key = var.encryption_key_secret_name != null ? var.encryption_key_secret_name : local.encryption_key_sm_path
            },
            var.encryption_key_secret_property != null ? { property = var.encryption_key_secret_property } : {},
          )
        }]
        target_deletion_policy = "Retain"
      },
      {
        name = "jwt-secret"
        data = [{
          secretKey = "jwt-secret"
          remoteRef = merge(
            { key = local.jwt_secret_remote_ref },
            var.jwt_secret_secret_property != null ? { property = var.jwt_secret_secret_property } : {},
          )
        }]
        target_deletion_policy = "Retain"
      },
      {
        name = "db-credentials"
        data = [{
          secretKey = "password"
          remoteRef = {
            key      = var.db.master_user_secret_arn
            property = var.db_password_secret_property
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
          remoteRef = merge(
            { key = local.license_key_remote_ref },
            var.license_key_secret_property != null ? { property = var.license_key_secret_property } : {},
          )
        }]
        target_deletion_policy = "Retain"
      },
    ] : [],
  )

  agent_sandbox_external_secret = var.enable_agent_sandbox ? {
    name   = "agent-sandbox"
    sm_key = "retool/${var.prefix}/agent-sandbox"
  } : null

  # Everything ESO is allowed to read: this module's own retool/{prefix}/*
  # namespace, the database credentials, plus any pre-existing secrets the
  # caller pointed us at (which live wherever their owner put them).
  eso_readable_secrets = distinct(compact(concat(
    [
      "arn:aws:secretsmanager:${var.region}:${data.aws_caller_identity.current.account_id}:secret:retool/${var.prefix}/*",
      var.db.master_user_secret_arn,
      var.encryption_key_secret_name,
      var.jwt_secret_secret_path,
      var.license_key_secret_path,
    ],
    var.extra_secret_read_arns,
  )))
}

data "aws_caller_identity" "current" {}

# Read access to just this deployment's secrets. The cluster's shared External
# Secrets Operator assumes it — selected per-deployment by spec.provider.aws.role
# on the SecretStore below — so one Retool deployment can never read another's
# secrets even though a single controller serves them all.
#
# Same-account assumption needs only this trust policy; IAM unions identity- and
# resource-based grants within an account. Across accounts, the controller's role
# also needs an identity policy allowing sts:AssumeRole on this ARN.
resource "aws_iam_role" "eso" {
  name = "${var.prefix}-eso"
  tags = local.all_tags

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { AWS = local.eso_trusted_principals }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })

  lifecycle {
    # An empty Principal list is a MalformedPolicyDocument at apply time, whether
    # or not this deployment creates the SecretStore, so require one
    # unconditionally and fail at plan with something actionable instead.
    precondition {
      condition     = length(local.eso_trusted_principals) > 0
      error_message = "No External Secrets Operator controller to trust. Pass eks = module.eks.outputs from an aws-eks instance with enable_external_secrets = true, or set eso_controller_role_arns to the IAM role ARN(s) of the controller that will reconcile this deployment's SecretStore."
    }
  }
}

resource "aws_iam_policy" "eso" {
  name        = "${var.prefix}-eso"
  description = "Allows External Secrets Operator to read Retool secrets from AWS Secrets Manager"
  tags        = local.all_tags

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret",
        "secretsmanager:ListSecretVersionIds",
        "secretsmanager:GetResourcePolicy",
        "secretsmanager:BatchGetSecretValue",
      ]
      Resource = local.eso_readable_secrets
    }]
  })
}

resource "aws_iam_role_policy_attachment" "eso" {
  role       = aws_iam_role.eso.name
  policy_arn = aws_iam_policy.eso.arn
}

# Namespaced SecretStore in the retool namespace, beside the ExternalSecrets that
# reference it. The cluster's shared ESO controller reconciles it using its own
# credentials as the base identity, then assumes spec.provider.aws.role to reach
# this deployment's secrets and nothing else.
resource "kubectl_manifest" "secret_store" {
  count = var.create_external_secrets ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "external-secrets.io/v1"
    kind       = local.secret_store_kind
    metadata = {
      name      = local.secret_store_name
      namespace = local.retool_namespace
    }
    spec = {
      provider = {
        aws = {
          service = "SecretsManager"
          region  = var.region
          role    = aws_iam_role.eso.arn
        }
      }
    }
  })

  depends_on = [kubernetes_namespace_v1.retool]
}

resource "kubectl_manifest" "external_secret" {
  for_each = var.create_external_secrets ? { for s in local.external_secrets : s.name => s } : {}

  yaml_body = yamlencode({
    apiVersion = "external-secrets.io/v1"
    kind       = "ExternalSecret"
    metadata = {
      name      = each.value.name
      namespace = local.retool_namespace
    }
    spec = {
      refreshInterval = "1m"
      secretStoreRef = {
        kind = local.secret_store_kind
        name = local.secret_store_name
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
  count = var.create_external_secrets && var.enable_agent_sandbox ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "external-secrets.io/v1"
    kind       = "ExternalSecret"
    metadata = {
      name      = local.agent_sandbox_external_secret.name
      namespace = local.retool_namespace
    }
    spec = {
      refreshInterval = "1m"
      secretStoreRef = {
        kind = local.secret_store_kind
        name = local.secret_store_name
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
  count = var.create_external_secrets ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "external-secrets.io/v1"
    kind       = "ExternalSecret"
    metadata = {
      name      = "extra-env-vars"
      namespace = local.retool_namespace
    }
    spec = {
      refreshInterval = "1m"
      secretStoreRef = {
        kind = local.secret_store_kind
        name = local.secret_store_name
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
