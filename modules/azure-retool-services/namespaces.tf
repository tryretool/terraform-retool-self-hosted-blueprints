# Single source of truth for the namespaces used across the Retool deployment.
# Computed here and exported via outputs.tf so retool-helm and the user-ingress
# module consume the same names instead of recomputing them. Created with
# kubectl_manifest (the kubectl provider is already configured for this module;
# the kubernetes provider is not).
locals {
  retool_namespace   = coalesce(var.retool_namespace, "${var.prefix}-retool")
  services_namespace = coalesce(var.services_namespace, "${var.prefix}-retool-services")
}

resource "kubectl_manifest" "retool_namespace" {
  count = var.create_namespaces ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "Namespace"
    metadata   = { name = local.retool_namespace }
  })
}

resource "kubectl_manifest" "services_namespace" {
  count = var.create_namespaces ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "Namespace"
    metadata   = { name = local.services_namespace }
  })
}
