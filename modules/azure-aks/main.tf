# ---------- Log Analytics ----------

resource "azurerm_log_analytics_workspace" "aks" {
  count = local.byo_cluster ? 0 : 1

  name                = "${var.prefix}-logs"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_analytics_retention_days
  tags                = var.tags
}

# ---------- AKS Cluster ----------

resource "azurerm_kubernetes_cluster" "main" {
  count = local.byo_cluster ? 0 : 1

  name                = "${var.prefix}-aks"
  location            = var.location
  resource_group_name = var.resource_group_name
  dns_prefix          = var.prefix
  kubernetes_version  = var.kubernetes_version
  node_resource_group = "${var.prefix}-aks-managed"
  tags                = var.tags

  # Workload Identity — Azure AD federated credentials allow k8s service accounts
  # to authenticate as Azure managed identities. This is the Azure equivalent of
  # EKS IRSA and GKE Workload Identity.
  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  api_server_access_profile {
    authorized_ip_ranges = length(var.api_server_authorized_ip_ranges) > 0 ? var.api_server_authorized_ip_ranges : null
  }

  default_node_pool {
    name                        = "default"
    temporary_name_for_rotation = "updating"
    auto_scaling_enabled        = true
    min_count                   = var.node_min_count
    max_count                   = var.node_max_count
    vm_size                     = var.node_vm_size
    os_disk_size_gb             = var.node_os_disk_size_gb
    vnet_subnet_id              = var.vnet.aks_subnet_id
    tags                        = var.tags

    upgrade_settings {
      max_surge = "10%"
    }
  }

  auto_scaler_profile {
    scan_interval                    = "10s"
    scale_down_delay_after_add       = "5m"
    scale_down_unneeded              = "5m"
    scale_down_utilization_threshold = 0.5
    expander                         = "least-waste"
  }

  # System-assigned identity — AKS auto-manages the necessary role assignments
  # (e.g. Network Contributor) without requiring the deploying user to have
  # Microsoft.Authorization/roleAssignments/* permissions.
  # Required from azurerm 5.0. "Manual" is the pre-5.0 behaviour: node pools are
  # the ones declared here, not provisioned automatically by AKS.
  node_provisioning_profile {
    mode = "Manual"
  }

  identity {
    type = "SystemAssigned"
  }

  # Standard Azure CNI — pods get IPs directly from the AKS VNet subnet. This
  # makes pod IPs routable from other VNet subnets (required for AGIC, which
  # configures Application Gateway to send traffic directly to pod IPs).
  # CNI Overlay is not compatible with AGIC because overlay pod IPs are not
  # VNet-routable.
  network_profile {
    network_plugin = "azure"
    service_cidr   = "10.96.0.0/16"
    dns_service_ip = "10.96.0.10"
  }

  oms_agent {
    log_analytics_workspace_id = azurerm_log_analytics_workspace.aks[0].id
  }
}
