locals {
  eso = {
    name                 = "external-secrets"
    namespace            = "external-secrets"
    service_account_name = "external-secrets"
  }

  retool_namespace = "default"

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
        remoteRef = { key = var.db_credentials_secret_name }
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

resource "azurerm_federated_identity_credential" "eso" {
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
  namespace        = local.eso.namespace
  create_namespace = true

  name       = local.eso.name
  repository = "https://charts.external-secrets.io"
  chart      = "external-secrets"
  version    = "0.12.1"
  wait       = true

  values = [yamlencode({
    installCRDs = true
    serviceAccount = {
      labels = {
        "azure.workload.identity/use" = "true"
      }
      annotations = {
        "azure.workload.identity/client-id" = azurerm_user_assigned_identity.eso.client_id
      }
    }
  })]
}

# ---------- ClusterSecretStore ----------

resource "kubectl_manifest" "secret_store" {
  yaml_body = yamlencode({
    apiVersion = "external-secrets.io/v1beta1"
    kind       = "ClusterSecretStore"
    metadata = {
      name = "azure-keyvault"
    }
    spec = {
      provider = {
        azurekv = {
          authType = "WorkloadIdentity"
          tenantId = data.azurerm_client_config.current.tenant_id
          vaultUrl = var.vnet.key_vault_uri
          serviceAccountRef = {
            name      = local.eso.service_account_name
            namespace = local.eso.namespace
          }
        }
      }
    }
  })

  depends_on = [helm_release.external_secrets]
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
        kind = "ClusterSecretStore"
        name = "azure-keyvault"
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
        kind = "ClusterSecretStore"
        name = "azure-keyvault"
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
  count = var.license_key != null ? 1 : 0

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
        kind = "ClusterSecretStore"
        name = "azure-keyvault"
      }
      target = {
        name           = "license-key"
        creationPolicy = "Owner"
        deletionPolicy = "Retain"
      }
      data = [{
        secretKey = "license-key"
        remoteRef = { key = "retool-${var.prefix}-license-key" }
      }]
    }
  })

  depends_on = [
    kubectl_manifest.secret_store,
    azurerm_key_vault_secret.license_key,
  ]
}
