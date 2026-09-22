locals {
  cert_manager = {
    name      = "cert-manager"
    namespace = "cert-manager"
  }
}

# A cluster-wide singleton: its CRDs and admission webhooks are cluster-scoped
# with fixed names, so only one copy can exist per cluster. The ALB controller
# needs it to issue the self-signed cert for its own webhook; we give it no IAM
# because it is not issuing external certs.
resource "helm_release" "cert_manager" {
  count = var.enable_cert_manager ? 1 : 0

  namespace        = local.cert_manager.namespace
  create_namespace = true

  name       = local.cert_manager.name
  repository = "https://charts.jetstack.io"
  chart      = "cert-manager"
  version    = "v1.21.0"
  timeout    = 600

  values = [
    jsonencode({
      crds = {
        enabled = var.install_crds
      }
      securityContext = {
        fsGroup = 1001
      }
    }),
    yamlencode(local.has_pod_scheduling ? merge(local.pod_scheduling, {
      webhook         = local.pod_scheduling
      cainjector      = local.pod_scheduling
      startupapicheck = local.pod_scheduling
    }) : {}),
  ]

  depends_on = [module.eks]
}
