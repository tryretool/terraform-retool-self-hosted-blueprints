locals {
  eso = {
    name                 = "external-secrets"
    namespace            = local.services_namespace
    service_account_name = "external-secrets"
  }

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
  count = var.enable_external_secrets ? 1 : 0

  name                = "${var.prefix}-eso-federated"
  resource_group_name = var.resource_group_name
  parent_id           = azurerm_user_assigned_identity.eso.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = var.aks.oidc_issuer_url
  subject             = "system:serviceaccount:${local.eso.namespace}:${local.eso.service_account_name}"
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

resource "helm_release" "external_secrets" {
  count = var.enable_external_secrets ? 1 : 0

  namespace        = local.eso.namespace
  create_namespace = false

  name       = local.eso.name
  repository = "https://charts.external-secrets.io"
  chart      = "external-secrets"
  version    = "0.12.1"
  wait       = true

  values = [yamlencode({
    installCRDs = var.install_crds
    serviceAccount = {
      labels = {
        "azure.workload.identity/use" = "true"
      }
      annotations = {
        "azure.workload.identity/client-id" = azurerm_user_assigned_identity.eso.client_id
      }
    }
  })]

  depends_on = [kubectl_manifest.services_namespace]
}

# ---------- SecretStore (namespaced) ----------
# Lives in the retool namespace alongside the ExternalSecrets. With no explicit
# serviceAccountRef, ESO's azurekv WorkloadIdentity auth uses the controller
# pod's projected token — the external-secrets controller SA carries the
# azure.workload.identity labels/annotation and is federated to the eso identity.
# (A namespaced SecretStore cannot reference a service account in another
# namespace, which is why the cross-namespace serviceAccountRef is dropped.)
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
        }
      }
    }
  })

  depends_on = [
    helm_release.external_secrets,
    kubectl_manifest.retool_namespace,
  ]
}

# ---------- ExternalSecrets ----------

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
  count = local.license_key_remote_ref != null ? 1 : 0

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
  count = var.enable_agent_sandbox ? 1 : 0

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
  count = var.enable_rr_blob ? 1 : 0

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
