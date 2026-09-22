# Restarts workloads when the ConfigMaps and Secrets they reference change.
# A cluster-wide singleton: it creates cluster-scoped RBAC with fixed names and
# watches every namespace.
resource "helm_release" "reloader" {
  count = var.enable_reloader ? 1 : 0

  namespace        = "reloader"
  create_namespace = true

  name       = "reloader"
  repository = "https://stakater.github.io/stakater-charts"
  chart      = "reloader"
  version    = "2.2.14"

  values = [
    yamlencode({
      reloader = {
        reloadOnCreate   = true
        reloadOnDelete   = true
        syncAfterRestart = true
        # Watches every workload in the cluster, not just Retool's. Set false to
        # restrict it to workloads carrying the reloader.stakater.com/* annotations.
        autoReloadAll = var.reloader_auto_reload_all
      }
    }),
    yamlencode(local.has_pod_scheduling ? { reloader = { deployment = local.pod_scheduling } } : {}),
  ]

  depends_on = [module.eks]
}
