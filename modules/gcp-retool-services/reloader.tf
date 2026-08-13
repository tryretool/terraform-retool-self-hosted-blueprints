resource "helm_release" "reloader" {
  namespace        = "default"
  create_namespace = false

  name       = "reloader"
  repository = var.reloader_chart.repository
  chart      = "reloader"
  version    = var.reloader_chart.version

  values = [yamlencode({
    image = {
      repository = var.reloader_chart.image_repository
      tag        = var.reloader_chart.image_tag
    }

    reloader = {
      reloadOnCreate   = true
      reloadOnDelete   = true
      syncAfterRestart = true
      autoReloadAll    = true
    }
  })]
}
