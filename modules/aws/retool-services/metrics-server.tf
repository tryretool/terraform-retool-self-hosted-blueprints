# Metrics server — provides resource metrics (CPU/memory) for kubectl top,
# HPA (Horizontal Pod Autoscaler), and VPA. Required for any autoscaling.

resource "helm_release" "metrics_server" {
  count = var.enable_metrics_server ? 1 : 0

  namespace        = "kube-system"
  create_namespace = false

  name       = "metrics-server"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  version    = "3.12.2"
  timeout    = 300

  depends_on = [
    helm_release.cert_manager,
  ]
}
