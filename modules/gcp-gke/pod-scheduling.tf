# Node placement shared by the cluster-singleton Helm charts installed here.
# Left empty by default so each chart keeps its own defaults.
locals {
  pod_scheduling = merge(
    length(var.pod_node_selector) > 0 ? { nodeSelector = var.pod_node_selector } : {},
    length(var.pod_tolerations) > 0 ? { tolerations = var.pod_tolerations } : {},
  )
  has_pod_scheduling = length(local.pod_scheduling) > 0
}
