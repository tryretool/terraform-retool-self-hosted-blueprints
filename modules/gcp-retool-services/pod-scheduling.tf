# Pod scheduling base, added to each chart's values as a SEPARATE values-list
# element (Helm deep-merges values) so the base values blocks stay untouched.
# Each helm_release shapes this per chart inline — multi-component charts repeat
# the nodeSelector/tolerations under each component key. When pod scheduling is
# unset the element is an empty `{}` doc, so chart defaults are kept. See the
# pod_node_selector / pod_tolerations variables in variables.tf.
locals {
  pod_scheduling = merge(
    length(var.pod_node_selector) > 0 ? { nodeSelector = var.pod_node_selector } : {},
    length(var.pod_tolerations) > 0 ? { tolerations = var.pod_tolerations } : {},
  )
  has_pod_scheduling = length(local.pod_scheduling) > 0
}
