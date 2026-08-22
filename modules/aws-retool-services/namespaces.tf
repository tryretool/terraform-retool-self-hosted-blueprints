# Single source of truth for the namespace this Retool deployment lives in.
# Computed here and exported via outputs.tf so retool-helm and the user-ingress
# module consume the same name instead of recomputing it. The cluster-wide
# operators are not per-deployment and live in their own namespaces, installed
# once per cluster by aws-eks.
locals {
  retool_namespace = coalesce(var.retool_namespace, "${var.prefix}-retool")
}

resource "kubernetes_namespace_v1" "retool" {
  count = var.create_namespace ? 1 : 0

  metadata {
    name = local.retool_namespace
  }
}
