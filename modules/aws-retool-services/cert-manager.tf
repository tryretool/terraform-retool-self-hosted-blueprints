locals {
  cert_manager = {
    name      = "${var.prefix}-cert-manager"
    namespace = local.services_namespace
  }
}

# alb controller needs cert-manager to give it a self-signed cert. we don't give
# it an IRSA or anything because it's not generating external certs. In a shared
# cluster that already runs cert-manager, set enable_cert_manager = false and the
# ALB controller will use the existing cluster-wide installation.
resource "helm_release" "cert_manager" {
  count = var.enable_cert_manager ? 1 : 0

  namespace        = local.cert_manager.namespace
  create_namespace = false

  name       = local.cert_manager.name
  repository = "https://charts.jetstack.io"
  chart      = "cert-manager"
  version    = "v1.21.0"
  skip_crds  = !var.install_crds
  timeout    = 600

  values = [
    jsonencode({
      installCRDs = var.install_crds
      crds = {
        enabled = var.install_crds
      }
      securityContext = {
        fsGroup = 1001
      }
      # scope to just the services and retool namespaces so multiple
      # cert-manager deployments can coexist in the cluster in shared-cluster
      # scenarios.
      namespace = local.cert_manager.namespace

    }),
    yamlencode(local.has_pod_scheduling ? merge(local.pod_scheduling, {
      webhook         = local.pod_scheduling
      cainjector      = local.pod_scheduling
      startupapicheck = local.pod_scheduling
    }) : {}),
  ]

  depends_on = [kubernetes_namespace_v1.services]
}
