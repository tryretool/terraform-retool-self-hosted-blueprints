resource "helm_release" "reloader" {
  count = var.enable_reloader ? 1 : 0

  namespace        = local.services_namespace
  create_namespace = false

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
        autoReloadAll    = true
        # Scope reloader to only watch the retool namespace so it never restarts
        # other tenants' workloads in a shared cluster. This also disables
        # ClusterRole creation which allows multiple deployments in different
        # namespaces within a shared cluster.
        namespaces = [local.retool_namespace]
        watchGlobally = false
      }
    }),
    yamlencode(local.has_pod_scheduling ? { reloader = { deployment = local.pod_scheduling } } : {}),
  ]

  depends_on = [kubernetes_namespace_v1.services]
}
