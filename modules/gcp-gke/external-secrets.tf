locals {
  external_secrets = {
    name                 = "external-secrets"
    namespace            = "external-secrets"
    service_account_name = "external-secrets"
  }

  eso_image = {
    repository = var.external_secrets_chart.image_repository
    tag        = var.external_secrets_chart.image_tag
  }
}

# A cluster-wide singleton: its CRDs and its ValidatingWebhookConfigurations have
# fixed cluster-scoped names, so a second release cannot coexist. It holds no
# Google API permissions of its own — each Retool deployment creates its own
# service account and points its namespaced SecretStore at it, so one deployment
# can never read another's secrets.
resource "helm_release" "external_secrets" {
  count = var.enable_external_secrets ? 1 : 0

  namespace        = local.external_secrets.namespace
  create_namespace = true

  name       = local.external_secrets.name
  repository = var.external_secrets_chart.repository
  chart      = "external-secrets"
  version    = var.external_secrets_chart.version
  wait       = true

  values = [
    yamlencode({
      installCRDs = var.install_crds

      crds = {
        # This chart templates its CRDs rather than shipping them in crds/, so
        # without this a `helm uninstall` deletes the cluster-scoped CRDs out
        # from under whatever is using them, and the garbage collector takes
        # every SecretStore and ExternalSecret with them.
        annotations = {
          "helm.sh/resource-policy" = "keep"
        }
      }

      # The operator, webhook and cert-controller are three deployments running the
      # same image, each reading its own values block. Setting only the top one
      # leaves the other two pulling from upstream.
      image          = local.eso_image
      certController = { image = local.eso_image }

      webhook = {
        image = local.eso_image

        # Terraform destroys the node pool before these releases, so the webhook
        # pods are gone by the time the CRs are deleted. Under the default Fail
        # policy the unreachable webhook rejects those deletes and the destroy
        # hangs.
        failurePolicy = "Ignore"
      }
    }),
    yamlencode(local.has_pod_scheduling ? merge(local.pod_scheduling, {
      webhook        = local.pod_scheduling
      certController = local.pod_scheduling
    }) : {}),
  ]

  depends_on = [google_container_node_pool.primary]
}
