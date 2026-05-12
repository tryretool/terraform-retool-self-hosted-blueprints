output "db_instance_fqdn" {
  description = "FQDN of the PostgreSQL Flexible Server (resolves via Private DNS Zone)"
  value       = azurerm_postgresql_flexible_server.main.fqdn
}

output "db_instance_port" {
  description = "Port for the PostgreSQL instance"
  value       = 5432
}

output "db_instance_name" {
  description = "Name of the database created inside the Flex Server"
  value       = var.database_name
}

output "db_instance_username" {
  description = "Master database username"
  value       = var.master_username
}

output "db_password_kv_secret_name" {
  description = "Name of the Key Vault secret containing the database password"
  value       = azurerm_key_vault_secret.pg_password.name
}
