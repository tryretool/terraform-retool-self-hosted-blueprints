# Metrics server — provides resource metrics (CPU/memory) for kubectl top,
# HPA (Horizontal Pod Autoscaler), and VPA. Required for any autoscaling.

resource "helm_release" "metrics_server" {
  count = var.enable_metrics_server ? 1 : 0

  namespace        = local.services_namespace
  create_namespace = false

  name       = "metrics-server"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  version    = "3.12.2"
  timeout    = 300

  values = [
    yamlencode(local.has_pod_scheduling ? local.pod_scheduling : {}),
  ]

  depends_on = [
    kubernetes_namespace_v1.services,
  ]
}
