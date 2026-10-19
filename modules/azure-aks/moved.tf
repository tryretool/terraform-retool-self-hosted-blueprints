# The cluster and the workspace that only exists alongside a cluster we create
# are now counted, so this module can adopt a pre-existing one instead
# (var.existing_cluster).

moved {
  from = azurerm_kubernetes_cluster.main
  to   = azurerm_kubernetes_cluster.main[0]
}

moved {
  from = azurerm_log_analytics_workspace.aks
  to   = azurerm_log_analytics_workspace.aks[0]
}
