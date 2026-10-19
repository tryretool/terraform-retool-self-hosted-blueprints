# Adopting a pre-existing cluster.
#
# When var.existing_cluster is set this module creates no cluster and no log
# analytics workspace, and instead resolves the same attributes from the live
# cluster so the operators below and this module's outputs behave identically in
# both modes.
#
# Everything else in this module reads local.cluster rather than
# azurerm_kubernetes_cluster.main directly, so neither branch is ever indexed
# when it has zero instances.

data "azurerm_client_config" "current" {}

data "azurerm_kubernetes_cluster" "existing" {
  count = local.byo_cluster ? 1 : 0

  name                = var.existing_cluster.name
  resource_group_name = coalesce(var.existing_cluster.resource_group_name, var.resource_group_name)
}

locals {
  byo_cluster = var.existing_cluster != null

  cluster_from_created = [for c in azurerm_kubernetes_cluster.main : {
    name                       = c.name
    endpoint                   = c.kube_config[0].host
    certificate_authority_data = c.kube_config[0].cluster_ca_certificate
    oidc_issuer_url            = c.oidc_issuer_url
    kubelet_identity_object_id = c.kubelet_identity[0].object_id
    node_resource_group        = c.node_resource_group
    client_certificate         = c.kube_config[0].client_certificate
    client_key                 = c.kube_config[0].client_key
    kube_config_raw            = c.kube_config_raw
    kube_admin_config_raw      = try(c.kube_admin_config_raw, null)
  }]

  cluster_from_existing = [for c in data.azurerm_kubernetes_cluster.existing : {
    name                       = c.name
    endpoint                   = c.kube_config[0].host
    certificate_authority_data = c.kube_config[0].cluster_ca_certificate
    # Empty when the adopted cluster has the OIDC issuer disabled, which the
    # precondition below turns into a readable failure.
    oidc_issuer_url            = try(c.oidc_issuer_url, "")
    kubelet_identity_object_id = c.kubelet_identity[0].object_id
    node_resource_group        = c.node_resource_group
    client_certificate         = c.kube_config[0].client_certificate
    client_key                 = c.kube_config[0].client_key
    kube_config_raw            = c.kube_config_raw
    kube_admin_config_raw      = try(c.kube_admin_config_raw, null)
  }]

  cluster = one(concat(local.cluster_from_created, local.cluster_from_existing))
}

# A cluster we create always has oidc_issuer_enabled and workload_identity_enabled
# set; one we adopt might not, and every identity this module and the
# per-deployment modules create is federated against that issuer.
check "adopted_cluster_workload_identity" {
  assert {
    condition     = !local.byo_cluster || local.cluster.oidc_issuer_url != ""
    error_message = "The adopted AKS cluster has no OIDC issuer URL. Retool's operators authenticate to Azure through workload identity federation; enable oidc_issuer_enabled and workload_identity_enabled on the cluster first."
  }
}
