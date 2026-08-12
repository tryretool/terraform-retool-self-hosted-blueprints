# Metrics server — provides resource metrics (CPU/memory) for kubectl top,
# HPA (Horizontal Pod Autoscaler), and VPA. Required for any autoscaling.
#
# It owns the cluster-wide metrics.k8s.io APIService, so it belongs with the
# other cluster-scoped addons here rather than with the per-deployment Retool
# services — only one copy can exist per cluster. Nothing downstream depends on
# how it is configured, so we take the EKS-managed addon and let AWS pick a
# version compatible with the cluster version (as with the other addons above).

resource "aws_eks_addon" "metrics_server" {
  count = var.enable_metrics_server ? 1 : 0

  cluster_name                = module.eks.cluster_name
  addon_name                  = "metrics-server"
  resolve_conflicts_on_create = "OVERWRITE"

  configuration_values = jsonencode({
    # The addon default tolerates CriticalAddonsOnly but not the Karpenter
    # controller taint; match the other kube-system addons so metrics-server can
    # schedule on the controller node group.
    tolerations = [
      {
        key    = "karpenter.sh/controller"
        value  = "true"
        effect = "NoSchedule"
      },
      {
        key      = "CriticalAddonsOnly"
        operator = "Exists"
      },
    ]
  })

  depends_on = [module.eks]
}
