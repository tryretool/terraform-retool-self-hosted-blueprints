locals {
  eso = {
    name                 = "${var.prefix}-external-secrets"
    namespace            = local.services_namespace
    service_account_name = "external-secrets"
  }

  # Namespaced SecretStore (lives in the retool namespace alongside the
  # ExternalSecrets that reference it), rather than a cluster-global
  # ClusterSecretStore whose fixed name would collide in a shared cluster.
  secret_store_kind = "SecretStore"
  secret_store_name = "retool-secretstore"

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

# Pod-identity wiring only makes sense for the operator we install ourselves.
# In a shared cluster (enable_external_secrets = false) the platform's ESO uses
# its own service account; attach the aws_iam_role.eso policy to it out of band.
resource "aws_eks_pod_identity_association" "eso" {
  count = var.enable_external_secrets ? 1 : 0

  cluster_name    = var.eks.name
  namespace       = local.eso.namespace
  service_account = local.eso.service_account_name
  role_arn        = aws_iam_role.eso.arn
}

resource "helm_release" "external_secrets" {
  count = var.enable_external_secrets ? 1 : 0

  namespace        = local.eso.namespace
  create_namespace = false

  name       = local.eso.name
  repository = "https://charts.external-secrets.io"
  chart      = "external-secrets"
  version    = "2.8.0"
  wait       = true

  values = [
    yamlencode({
      # avoid creating cluster-wide ClusterRole resources
      scopedRBAC = true
      rbac = {
        servicebindings = {
          create = false
        }
      }
      # only resolve secret resources in the retool namespace, even though ESO
      # itself is deployed into the services namespace, as the secrets need to
      # live with the workloads that consume them.
      scopedNamespace = local.retool_namespace
      # don't install CRDs, i.e. in shared-cluster envs
      installCRDs = var.install_crds
      webhook = {
        # don't create validating webhook, as ValidatingWebhookConfiguration is
        # a cluster-scoped resource and its name is hardcoded in the chart,
        # making it prevent multiple deployments in a shared cluster
        create = false
        # use the separately installed cert-manager instead of the built-in
        # certController, because ESO's certController requires a ClusterRole that
        # makes it unfriendly to multiple deployments sharing a cluster
        certManager = {
          enabled = true
        }
      }
    }),
    yamlencode(local.has_pod_scheduling ? merge(local.pod_scheduling, {
      webhook        = local.pod_scheduling
      certController = local.pod_scheduling
    }) : {}),
  ]

  depends_on = [kubernetes_namespace_v1.services]
}

# Namespaced SecretStore in the retool namespace. ESO authenticates with the
# controller's own credentials (the pod-identity association above), so no
# per-store serviceAccountRef is needed. Always created — even when the operator
# is provided by the platform — since it is app-specific configuration the
# (platform or bundled) ESO reconciles.
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
        }
      }
    }
  })

  depends_on = [
    helm_release.external_secrets,
    kubernetes_namespace_v1.retool,
  ]
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

  depends_on = [kubectl_manifest.secret_store[0]]
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

  depends_on = [kubectl_manifest.secret_store[0]]
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

  depends_on = [kubectl_manifest.secret_store[0]]
}
