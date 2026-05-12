# Output shape mirrors the GKE and EKS modules' cluster output for consistency.
output "cluster" {
  description = "AKS cluster details"
  value = {
    name = azurerm_kubernetes_cluster.main.name

    # Used to configure kubernetes/helm providers.
    endpoint                   = azurerm_kubernetes_cluster.main.kube_config[0].host
    certificate_authority_data = azurerm_kubernetes_cluster.main.kube_config[0].cluster_ca_certificate

    # Workload Identity — downstream modules use this to create
    # azurerm_federated_identity_credential resources linking k8s service
    # accounts to Azure managed identities.
    oidc_issuer_url = azurerm_kubernetes_cluster.main.oidc_issuer_url

    # Kubelet identity for granting node-level access (e.g. ACR pull).
    kubelet_identity_object_id = azurerm_kubernetes_cluster.main.kubelet_identity[0].object_id

    # The auto-created node resource group (contains VMSS, disks, NICs).
    node_resource_group = azurerm_kubernetes_cluster.main.node_resource_group

    # Client credentials for provider auth.
    client_certificate    = azurerm_kubernetes_cluster.main.kube_config[0].client_certificate
    client_key            = azurerm_kubernetes_cluster.main.kube_config[0].client_key
    kube_config_raw       = azurerm_kubernetes_cluster.main.kube_config_raw
    kube_admin_config_raw = try(azurerm_kubernetes_cluster.main.kube_admin_config_raw, null)
  }
}
