# Single source of truth for the namespaces used across the Retool deployment.
# Computed here and exported via outputs.tf so retool-helm and the user-ingress
# module consume the same names instead of recomputing them.
locals {
  retool_namespace   = coalesce(var.retool_namespace, "${var.prefix}-retool")
  services_namespace = coalesce(var.services_namespace, "${var.prefix}-retool-services")
}

resource "kubernetes_namespace_v1" "retool" {
  count = var.create_namespaces ? 1 : 0

  metadata {
    name = local.retool_namespace
  }
}

resource "kubernetes_namespace_v1" "services" {
  count = var.create_namespaces ? 1 : 0

  metadata {
    name = local.services_namespace
  }
}
