locals {
  outputs = {
    vnet_id           = azurerm_virtual_network.main.id
    vnet_name         = azurerm_virtual_network.main.name
    aks_subnet_id     = azurerm_subnet.aks.id
    postgres_subnet_id = azurerm_subnet.postgres.id
    appgw_subnet_id   = azurerm_subnet.appgw.id
    key_vault_id      = azurerm_key_vault.main.id
    key_vault_uri     = azurerm_key_vault.main.vault_uri
    key_vault_name    = azurerm_key_vault.main.name
  }
}

output "vnet_id" {
  description = "ID of the VNet"
  value       = local.outputs.vnet_id
}

output "vnet_name" {
  description = "Name of the VNet"
  value       = local.outputs.vnet_name
}

output "aks_subnet_id" {
  description = "ID of the AKS node pool subnet"
  value       = local.outputs.aks_subnet_id
}

output "postgres_subnet_id" {
  description = "ID of the PostgreSQL Flexible Server delegated subnet"
  value       = local.outputs.postgres_subnet_id
}

output "appgw_subnet_id" {
  description = "ID of the Application Gateway dedicated subnet"
  value       = local.outputs.appgw_subnet_id
}

output "key_vault_id" {
  description = "ID of the shared Key Vault"
  value       = local.outputs.key_vault_id
}

output "key_vault_uri" {
  description = "URI of the shared Key Vault (e.g. https://name.vault.azure.net)"
  value       = local.outputs.key_vault_uri
}

output "key_vault_name" {
  description = "Name of the shared Key Vault"
  value       = local.outputs.key_vault_name
}

output "outputs" {
  value       = local.outputs
  description = "Structured VNet outputs for composition with downstream modules."
}
