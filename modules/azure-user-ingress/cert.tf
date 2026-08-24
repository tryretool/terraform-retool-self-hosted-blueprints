# ---------- cert-manager + Let's Encrypt (conditional on enable_https) ----------
# Azure has no equivalent to ACM or Google Certificate Manager for auto-provisioned
# TLS certs. cert-manager with Let's Encrypt DNS-01 challenge (via Azure DNS) fills
# this gap. The cert is stored as a K8s TLS Secret and referenced by AGIC via
# Ingress TLS annotations.

locals {
  # Namespace sourced from the retool-services outputs (single source of truth),
  # with a prefix-based fallback when this module is used standalone.
  retool_namespace = coalesce(try(var.retool_services.retool_namespace, null), "${var.prefix}-retool")

  # Prefixed so several AGIC instances can coexist: the IngressClass name and the
  # controller value both have to be unique per Application Gateway.
  ingress_class_name        = coalesce(var.ingress_class_name, "${var.prefix}-agic")
  agic_service_account_name = "${var.prefix}-ingress-azure"

  # cert-manager itself is a cluster singleton installed by azure-aks. What is
  # per-deployment is the identity that reaches THIS deployment's DNS zone, and
  # the Issuer that names it. We create both unless the caller points at an
  # issuer they manage themselves.
  manage_issuer = var.enable_https && var.cluster_issuer_name == null

  # A namespaced Issuer rather than a ClusterIssuer: the name would otherwise be
  # cluster-global and collide between deployments, as would its ACME account key.
  issuer_kind = var.cluster_issuer_name == null ? "Issuer" : "ClusterIssuer"
  issuer_name = coalesce(var.cluster_issuer_name, "${var.prefix}-letsencrypt")
}

resource "azurerm_user_assigned_identity" "cert_manager" {
  count = local.manage_issuer ? 1 : 0

  name                = "${var.prefix}-cert-manager-identity"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

# cert-manager has no per-Issuer service account indirection: an Issuer names a
# managed identity and the controller exchanges its OWN projected token for it.
# So this credential federates against the shared controller's service account,
# which azure-aks exports, and the DNS grant below is what keeps the scope of
# that identity limited to this deployment's zone.
resource "azurerm_federated_identity_credential" "cert_manager" {
  count = local.manage_issuer ? 1 : 0

  name                      = "${var.prefix}-cert-manager-federated"
  user_assigned_identity_id = azurerm_user_assigned_identity.cert_manager[0].id
  audience                  = ["api://AzureADTokenExchange"]
  issuer                    = var.aks.oidc_issuer_url
  subject                   = var.aks.cert_manager_service_account_subject
}

# cert-manager needs DNS Zone Contributor to create TXT records for DNS-01 challenges.
resource "azurerm_role_assignment" "cert_manager_dns_contributor" {
  count = local.manage_issuer ? 1 : 0

  scope                = azurerm_dns_zone.main.id
  role_definition_name = "DNS Zone Contributor"
  principal_id         = azurerm_user_assigned_identity.cert_manager[0].principal_id
}

data "azurerm_subscription" "current" {}

# Namespaced Issuer for Let's Encrypt using the Azure DNS solver.
resource "kubectl_manifest" "issuer" {
  count = local.manage_issuer ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "cert-manager.io/v1"
    kind       = "Issuer"
    metadata = {
      name      = local.issuer_name
      namespace = local.retool_namespace
    }
    spec = {
      acme = {
        server = "https://acme-v02.api.letsencrypt.org/directory"
        privateKeySecretRef = {
          name = "${var.prefix}-letsencrypt-account-key"
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

}

# Certificate resource → creates a K8s TLS Secret referenced by the Ingress.
# Lives in the retool namespace beside the Ingress that mounts the TLS secret.
resource "kubectl_manifest" "certificate" {
  count = var.enable_https ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "cert-manager.io/v1"
    kind       = "Certificate"
    metadata = {
      name      = "${var.prefix}-tls"
      namespace = local.retool_namespace
    }
    spec = {
      secretName = "${var.prefix}-tls"
      issuerRef = {
        name = local.issuer_name
        kind = local.issuer_kind
      }
      dnsNames = [
        var.domain_name,
        "*.${var.domain_name}",
      ]
    }
  })

  depends_on = [kubectl_manifest.issuer]
}
