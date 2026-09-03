locals {
  external_secrets = {
    name                 = "external-secrets"
    namespace            = "external-secrets"
    service_account_name = "external-secrets"
  }
}

# A cluster-wide singleton: its CRDs and its ValidatingWebhookConfigurations have
# fixed cluster-scoped names, so a second release cannot coexist.
#
# The controller holds no Key Vault permission of its own. Each Retool deployment
# creates its own managed identity, federates it to a service account in its own
# namespace, and names that service account on its SecretStore — so the
# controller reads only what that deployment granted it, and one deployment can
# never reach another's secrets.
resource "helm_release" "external_secrets" {
  count = var.enable_external_secrets ? 1 : 0

  namespace        = local.external_secrets.namespace
  create_namespace = true

  name       = local.external_secrets.name
  repository = "https://charts.external-secrets.io"
  chart      = "external-secrets"
  version    = "2.8.0"
  wait       = true

  values = [
    yamlencode({
      installCRDs    = var.install_crds
      serviceAccount = { name = local.external_secrets.service_account_name }

      crds = {
        unsafeServeV1Beta1 = var.external_secrets_serve_v1beta1
        # This chart templates its CRDs rather than shipping them in crds/, so
        # without this a `helm uninstall` — including the one that retires an
        # older release of this same operator — deletes the cluster-scoped CRDs
        # out from under whatever is using them, and the garbage collector takes
        # every SecretStore and ExternalSecret with them.
        annotations = {
          "helm.sh/resource-policy" = "keep"
        }
      }
    }),
    yamlencode(local.has_pod_scheduling ? merge(local.pod_scheduling, {
      webhook        = local.pod_scheduling
      certController = local.pod_scheduling
    }) : {}),
  ]

  depends_on = [azurerm_kubernetes_cluster.main]
}
