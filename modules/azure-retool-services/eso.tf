locals {
  # Service account this deployment's SecretStore names. Nothing runs as it —
  # the cluster's shared External Secrets Operator mints a token for it and
  # exchanges that for this deployment's managed identity, so one deployment can
  # only read the secrets it was granted.
  eso_service_account_name = "retool-eso"

  # Namespaced SecretStore (lives in the retool namespace alongside the
  # ExternalSecrets that reference it), rather than a cluster-global
  # ClusterSecretStore whose fixed name would collide in a shared cluster.
  secret_store_kind = "SecretStore"
  secret_store_name = "retool-secretstore"

  # Key Vault secret name for the license key, sourced from either the managed
  # secret (var.license_key) or an existing one (var.license_key_secret_path).
  # null when neither is set (free-tier mode).
  license_key_remote_ref = (
    nonsensitive(var.license_key != null)
    ? "retool-${var.prefix}-license-key"
    : var.license_key_secret_path
  )

  external_secrets = [
    {
      name = "encryption-key"
      data = [{
        secretKey = "encryption-key"
        remoteRef = { key = local.encryption_key_secret_ref }
      }]
      target_deletion_policy = "Retain"
    },
    {
      name = "jwt-secret"
      data = [{
        secretKey = "jwt-secret"
        remoteRef = { key = "retool-${var.prefix}-jwt-secret" }
      }]
      target_deletion_policy = "Retain"
    },
    {
      name = "db-credentials"
      data = [{
        secretKey = "password"
        remoteRef = { key = var.db.master_secret_name }
      }]
      target_deletion_policy = "Retain"
    },
  ]
}

# ---------- ESO Workload Identity ----------
# Create a managed identity for ESO and federate it with the ESO k8s service account.
# This is the Azure equivalent of GCP Workload Identity binding and EKS IRSA.

resource "azurerm_user_assigned_identity" "eso" {
  name                = "${var.prefix}-eso-identity"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

# Federation only makes sense for the operator we install ourselves. In a shared
# cluster (enable_external_secrets = false) the platform's ESO uses its own
# identity; grant it the eso managed identity's Key Vault access policy (this
# module always creates that access policy and exports the identity client id).
resource "azurerm_federated_identity_credential" "eso" {
  name                      = "${var.prefix}-eso-federated"
  user_assigned_identity_id = azurerm_user_assigned_identity.eso.id
  audience                  = ["api://AzureADTokenExchange"]
  issuer                    = var.aks.oidc_issuer_url
  subject                   = "system:serviceaccount:${local.retool_namespace}:${local.eso_service_account_name}"
}

# Grant ESO read access to secrets in the Key Vault via access policy.
# Uses access policy (not RBAC) to avoid requiring Owner/UAA permissions.
data "azurerm_client_config" "current" {}

resource "azurerm_key_vault_access_policy" "eso" {
  key_vault_id = var.vnet.key_vault_id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = azurerm_user_assigned_identity.eso.principal_id

  secret_permissions = ["Get", "List"]
}

# ---------- ESO Helm release ----------

# Annotated so the shared controller's token exchange lands on this
# deployment's managed identity.
resource "kubernetes_service_account_v1" "eso" {
  metadata {
    name      = local.eso_service_account_name
    namespace = local.retool_namespace

    annotations = {
      "azure.workload.identity/client-id" = azurerm_user_assigned_identity.eso.client_id
      "azure.workload.identity/tenant-id" = data.azurerm_client_config.current.tenant_id
    }
  }

  depends_on = [kubernetes_namespace_v1.retool]
}

# ---------- SecretStore (namespaced) ----------
# Lives in the retool namespace alongside the ExternalSecrets it serves. Naming a
# service account in the same namespace makes the cluster's shared controller
# mint a token for it and assume this deployment's identity, rather than falling
# back to the controller's own — which is what keeps deployments isolated from
# each other's secrets.
# Always created so a platform-provided ESO reconciles it in shared clusters.
resource "kubectl_manifest" "secret_store" {
  yaml_body = yamlencode({
    apiVersion = "external-secrets.io/v1beta1"
    kind       = local.secret_store_kind
    metadata = {
      name      = local.secret_store_name
      namespace = local.retool_namespace
    }
    spec = {
      provider = {
        azurekv = {
          authType = "WorkloadIdentity"
          tenantId = data.azurerm_client_config.current.tenant_id
          vaultUrl = var.vnet.key_vault_uri
          serviceAccountRef = {
            name = local.eso_service_account_name
          }
        }
      }
    }
  })

  depends_on = [
    kubernetes_service_account_v1.eso,
    kubernetes_namespace_v1.retool,
  ]
}

# ---------- ExternalSecrets ----------

resource "kubectl_manifest" "external_secret" {
  for_each = var.create_external_secrets ? { for s in local.external_secrets : s.name => s } : {}

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

resource "kubectl_manifest" "external_secret_extra_env_vars" {
  count = var.create_external_secrets ? 1 : 0

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
          key = "retool-${var.prefix}-extra-env-vars"
        }
      }]
    }
  })

  depends_on = [kubectl_manifest.secret_store]
}

# License key ExternalSecret (conditional)
resource "kubectl_manifest" "external_secret_license_key" {
  count = var.create_external_secrets && local.license_key_remote_ref != null ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "external-secrets.io/v1beta1"
    kind       = "ExternalSecret"
    metadata = {
      name      = "license-key"
      namespace = local.retool_namespace
    }
    spec = {
      refreshInterval = "1m"
      secretStoreRef = {
        kind = local.secret_store_kind
        name = local.secret_store_name
      }
      target = {
        name           = "license-key"
        creationPolicy = "Owner"
        deletionPolicy = "Retain"
      }
      data = [{
        secretKey = "license-key"
        remoteRef = { key = local.license_key_remote_ref }
      }]
    }
  })

  depends_on = [
    kubectl_manifest.secret_store,
    azurerm_key_vault_secret.license_key,
  ]
}

# Agent sandbox ExternalSecret (conditional)
resource "kubectl_manifest" "external_secret_agent_sandbox" {
  count = var.create_external_secrets && var.enable_agent_sandbox ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "external-secrets.io/v1beta1"
    kind       = "ExternalSecret"
    metadata = {
      name      = "agent-sandbox"
      namespace = local.retool_namespace
    }
    spec = {
      refreshInterval = "1m"
      secretStoreRef = {
        kind = local.secret_store_kind
        name = local.secret_store_name
      }
      target = {
        name           = "agent-sandbox"
        creationPolicy = "Owner"
        deletionPolicy = "Retain"
      }
      dataFrom = [{
        extract = {
          key = "retool-${var.prefix}-agent-sandbox"
        }
      }]
    }
  })

  depends_on = [
    kubectl_manifest.secret_store,
    azurerm_key_vault_secret.agent_sandbox,
  ]
}

# RR Blob ExternalSecret (conditional)
resource "kubectl_manifest" "external_secret_rr_blob" {
  count = var.create_external_secrets && var.enable_rr_blob ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "external-secrets.io/v1beta1"
    kind       = "ExternalSecret"
    metadata = {
      name      = "rr-blob-credentials"
      namespace = local.retool_namespace
    }
    spec = {
      refreshInterval = "1m"
      secretStoreRef = {
        kind = local.secret_store_kind
        name = local.secret_store_name
      }
      target = {
        name           = "rr-blob-credentials"
        creationPolicy = "Owner"
        deletionPolicy = "Retain"
      }
      dataFrom = [{
        extract = {
          key = "retool-${var.prefix}-rr-blob"
        }
      }]
    }
  })

  depends_on = [
    kubectl_manifest.secret_store,
    azurerm_key_vault_secret.rr_blob,
  ]
}
