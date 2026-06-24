resource "helm_release" "reloader" {
  count = var.enable_reloader ? 1 : 0

  namespace        = local.services_namespace
  create_namespace = false

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
        autoReloadAll    = true
        # Scope reloader to only watch the retool namespace so it never restarts
        # other tenants' workloads in a shared cluster. Every namespace carries the
        # immutable `kubernetes.io/metadata.name` label, so we select by that.
        namespaceSelector = "kubernetes.io/metadata.name=${local.retool_namespace}"
      }
    }),
    yamlencode(local.has_pod_scheduling ? { reloader = { deployment = local.pod_scheduling } } : {}),
  ]

  depends_on = [kubernetes_namespace_v1.services]
}
