resource "helm_release" "reloader" {
  namespace        = "default"
  create_namespace = false

  name       = "reloader"
  repository = "https://stakater.github.io/stakater-charts"
  chart      = "reloader"
  version    = "2.2.9"

  values = [yamlencode({
    reloader = {
      reloadOnCreate   = true
      reloadOnDelete   = true
      syncAfterRestart = true
      autoReloadAll    = true
    }
  })]
}
