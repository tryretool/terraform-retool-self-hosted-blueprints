# Restarts workloads when the ConfigMaps and Secrets they reference change.
# A cluster-wide singleton: it creates cluster-scoped RBAC with fixed names and
# watches every namespace.
resource "helm_release" "reloader" {
  count = var.enable_reloader ? 1 : 0

  namespace        = "reloader"
  create_namespace = true

  name       = "reloader"
  repository = var.reloader_chart.repository
  chart      = "reloader"
  version    = var.reloader_chart.version

  values = [
    yamlencode({
      image = {
        repository = var.reloader_chart.image_repository
        tag        = var.reloader_chart.image_tag
      }

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
    # deployment.labels lands on both the Deployment and its pod template.
    yamlencode(length(var.pod_labels) > 0 ? { reloader = { deployment = { labels = var.pod_labels } } } : {}),
  ]

  depends_on = [google_container_node_pool.primary]
}
