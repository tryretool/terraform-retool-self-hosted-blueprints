# ---------- cert-manager + Let's Encrypt (conditional on enable_https) ----------
# Azure has no equivalent to ACM or Google Certificate Manager for auto-provisioned
# TLS certs. cert-manager with Let's Encrypt DNS-01 challenge (via Azure DNS) fills
# this gap. The cert is stored as a K8s TLS Secret and referenced by AGIC via
# Ingress TLS annotations.

locals {
  # Namespaces sourced from the retool-services outputs (single source of truth),
  # with prefix-based fallbacks when this module is used standalone.
  retool_namespace   = coalesce(try(var.retool_services.retool_namespace, null), "${var.prefix}-retool")
  services_namespace = coalesce(try(var.retool_services.services_namespace, null), "${var.prefix}-retool-services")

  # This module installs cert-manager + its own ClusterIssuer only when HTTPS is
  # on and the caller hasn't pointed at an existing issuer. Otherwise the TLS
  # Certificate references whatever cluster_issuer_name resolves to.
  manage_cert_manager = var.enable_https && var.enable_cert_manager && var.cluster_issuer_name == null
  cluster_issuer_name = coalesce(var.cluster_issuer_name, "letsencrypt-prod")
}

resource "azurerm_user_assigned_identity" "cert_manager" {
  count = local.manage_cert_manager ? 1 : 0

  name                = "${var.prefix}-cert-manager-identity"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_federated_identity_credential" "cert_manager" {
  count = local.manage_cert_manager ? 1 : 0

  name                = "${var.prefix}-cert-manager-federated"
  resource_group_name = var.resource_group_name
  parent_id           = azurerm_user_assigned_identity.cert_manager[0].id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = var.aks.oidc_issuer_url
  subject             = "system:serviceaccount:${local.services_namespace}:cert-manager"
}

# cert-manager needs DNS Zone Contributor to create TXT records for DNS-01 challenges.
resource "azurerm_role_assignment" "cert_manager_dns_contributor" {
  count = local.manage_cert_manager ? 1 : 0

  scope                = azurerm_dns_zone.main.id
  role_definition_name = "DNS Zone Contributor"
  principal_id         = azurerm_user_assigned_identity.cert_manager[0].principal_id
}

resource "helm_release" "cert_manager" {
  count = local.manage_cert_manager ? 1 : 0

  namespace        = local.services_namespace
  create_namespace = false

  name       = "cert-manager"
  repository = "https://charts.jetstack.io"
  chart      = "cert-manager"
  version    = "v1.17.1"
  wait       = true

  values = [
    yamlencode({
      installCRDs = var.install_crds
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
    }),
    yamlencode(local.has_pod_scheduling ? merge(local.pod_scheduling, {
      webhook         = local.pod_scheduling
      cainjector      = local.pod_scheduling
      startupapicheck = local.pod_scheduling
    }) : {}),
  ]
}

data "azurerm_subscription" "current" {}

# ClusterIssuer for Let's Encrypt using Azure DNS solver.
resource "kubectl_manifest" "cluster_issuer" {
  count = local.manage_cert_manager ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "cert-manager.io/v1"
    kind       = "ClusterIssuer"
    metadata = {
      name = local.cluster_issuer_name
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
        name = local.cluster_issuer_name
        kind = "ClusterIssuer"
      }
      dnsNames = [
        var.domain_name,
        "*.${var.domain_name}",
      ]
    }
  })

  depends_on = [kubectl_manifest.cluster_issuer]
}
