output "vnet_id" {
  description = "ID of the VNet"
  value       = azurerm_virtual_network.main.id
}

output "vnet_name" {
  description = "Name of the VNet"
  value       = azurerm_virtual_network.main.name
}

output "aks_subnet_id" {
  description = "ID of the AKS node pool subnet"
  value       = azurerm_subnet.aks.id
}

output "postgres_subnet_id" {
  description = "ID of the PostgreSQL Flexible Server delegated subnet"
  value       = azurerm_subnet.postgres.id
}

output "appgw_subnet_id" {
  description = "ID of the Application Gateway dedicated subnet"
  value       = azurerm_subnet.appgw.id
}

output "key_vault_id" {
  description = "ID of the shared Key Vault"
  value       = azurerm_key_vault.main.id
}

output "key_vault_uri" {
  description = "URI of the shared Key Vault (e.g. https://name.vault.azure.net)"
  value       = azurerm_key_vault.main.vault_uri
}

output "key_vault_name" {
  description = "Name of the shared Key Vault"
  value       = azurerm_key_vault.main.name
}
