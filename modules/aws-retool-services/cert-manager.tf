locals {
  cert_manager = {
    name      = "cert-manager"
    namespace = "cert-manager"
  }
}

# alb controller needs cert-manager to give it a self-signed cert. we don't give
# it an IRSA or anything because it's not generating external certs.
resource "helm_release" "cert_manager" {
  namespace        = local.cert_manager.namespace
  create_namespace = true

  name       = local.cert_manager.name
  repository = "https://charts.jetstack.io"
  chart      = "cert-manager"
  version    = "v1.11.0"
  timeout    = 600

  values = [jsonencode({
    installCRDs = true
    securityContext = {
      fsGroup = 1001
    }
  })]
}
