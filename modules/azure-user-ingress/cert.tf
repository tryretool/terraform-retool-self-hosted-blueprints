# ---------- cert-manager + Let's Encrypt (conditional on enable_https) ----------
# Azure has no equivalent to ACM or Google Certificate Manager for auto-provisioned
# TLS certs. cert-manager with Let's Encrypt DNS-01 challenge (via Azure DNS) fills
# this gap. The cert is stored as a K8s TLS Secret and referenced by AGIC via
# Ingress TLS annotations.

resource "azurerm_user_assigned_identity" "cert_manager" {
  count = var.enable_https ? 1 : 0

  name                = "${var.prefix}-cert-manager-identity"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_federated_identity_credential" "cert_manager" {
  count = var.enable_https ? 1 : 0

  name                = "${var.prefix}-cert-manager-federated"
  resource_group_name = var.resource_group_name
  parent_id           = azurerm_user_assigned_identity.cert_manager[0].id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = var.aks.oidc_issuer_url
  subject             = "system:serviceaccount:cert-manager:cert-manager"
}

# cert-manager needs DNS Zone Contributor to create TXT records for DNS-01 challenges.
resource "azurerm_role_assignment" "cert_manager_dns_contributor" {
  count = var.enable_https ? 1 : 0

  scope                = azurerm_dns_zone.main.id
  role_definition_name = "DNS Zone Contributor"
  principal_id         = azurerm_user_assigned_identity.cert_manager[0].principal_id
}

resource "helm_release" "cert_manager" {
  count = var.enable_https ? 1 : 0

  namespace        = "cert-manager"
  create_namespace = true

  name       = "cert-manager"
  repository = "https://charts.jetstack.io"
  chart      = "cert-manager"
  version    = "v1.17.1"
  wait       = true

  values = [yamlencode({
    installCRDs = true
    serviceAccount = {
      labels = {
        "azure.workload.identity/use" = "true"
      }
      annotations = {
        "azure.workload.identity/client-id" = azurerm_user_assigned_identity.cert_manager[0].client_id
      }
    }
    podLabels = {
      "azure.workload.identity/use" = "true"
    }
  })]
}

data "azurerm_subscription" "current" {}

# ClusterIssuer for Let's Encrypt using Azure DNS solver.
resource "kubectl_manifest" "cluster_issuer" {
  count = var.enable_https ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "cert-manager.io/v1"
    kind       = "ClusterIssuer"
    metadata = {
      name = "letsencrypt-prod"
    }
    spec = {
      acme = {
        server = "https://acme-v02.api.letsencrypt.org/directory"
        privateKeySecretRef = {
          name = "letsencrypt-prod-account-key"
        }
        solvers = [{
          dns01 = {
            azureDNS = {
              subscriptionID    = data.azurerm_subscription.current.subscription_id
              resourceGroupName = var.resource_group_name
              hostedZoneName    = azurerm_dns_zone.main.name
              managedIdentity = {
                clientID = azurerm_user_assigned_identity.cert_manager[0].client_id
              }
            }
          }
        }]
      }
    }
  })

  depends_on = [helm_release.cert_manager]
}

# Certificate resource → creates a K8s TLS Secret referenced by the Gateway.
resource "kubectl_manifest" "certificate" {
  count = var.enable_https ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "cert-manager.io/v1"
    kind       = "Certificate"
    metadata = {
      name      = "${var.prefix}-tls"
      namespace = "default"
    }
    spec = {
      secretName = "${var.prefix}-tls"
      issuerRef = {
        name = "letsencrypt-prod"
        kind = "ClusterIssuer"
      }
      dnsNames = [var.domain_name]
    }
  })

  depends_on = [kubectl_manifest.cluster_issuer]
}
