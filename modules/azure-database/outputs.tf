locals {
  outputs = {
    address            = azurerm_postgresql_flexible_server.main.fqdn
    port               = 5432
    name               = var.database_name
    username           = var.master_username
    master_secret_name = azurerm_key_vault_secret.pg_password.name
  }
}

output "address" {
  description = "FQDN of the PostgreSQL Flexible Server (resolves via Private DNS Zone)"
  value       = local.outputs.address
}

output "port" {
  description = "Port for the PostgreSQL instance"
  value       = local.outputs.port
}

output "name" {
  description = "Name of the database created inside the Flex Server"
  value       = local.outputs.name
}

output "username" {
  description = "Master database username"
  value       = local.outputs.username
}

output "master_secret_name" {
  description = "Name of the Key Vault secret containing the database password"
  value       = local.outputs.master_secret_name
}

output "outputs" {
  value       = local.outputs
  description = "Structured database outputs for composition with downstream modules."
}
