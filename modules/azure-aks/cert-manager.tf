locals {
  cert_manager = {
    name                 = "cert-manager"
    namespace            = "cert-manager"
    service_account_name = "cert-manager"
  }

  # The subject each per-deployment managed identity federates against. Azure
  # has no ACM equivalent, so cert-manager issues Let's Encrypt certs via DNS-01
  # against Azure DNS — and the zone is per-deployment. azure-user-ingress
  # therefore creates its own identity, grants it DNS Zone Contributor on its own
  # zone, and federates it to this one service account; cert-manager exchanges
  # its own token for whichever identity the Issuer names.
  cert_manager_service_account_subject = "system:serviceaccount:${local.cert_manager.namespace}:${local.cert_manager.service_account_name}"
}

# A cluster-wide singleton: its CRDs and the cert-manager-webhook admission
# configurations are cluster-scoped with fixed names.
resource "helm_release" "cert_manager" {
  count = var.enable_cert_manager ? 1 : 0

  namespace        = local.cert_manager.namespace
  create_namespace = true

  name       = local.cert_manager.name
  repository = "https://charts.jetstack.io"
  chart      = "cert-manager"
  version    = "v1.21.0"
  timeout    = 600
  wait       = true

  values = [
    jsonencode({
      crds = {
        enabled = var.install_crds
      }
      securityContext = {
        fsGroup = 1001
      }
      # Lets cert-manager exchange its projected service account token for the
      # managed identity an Issuer names.
      serviceAccount = {
        labels = {
          "azure.workload.identity/use" = "true"
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

  depends_on = [azurerm_kubernetes_cluster.main]
}
