# ---------- Private DNS Zone ----------
# Required for PostgreSQL Flexible Server VNet integration. The Flex Server
# registers its FQDN in this zone so pods in the VNet can resolve it.

# The zone name must NOT match the server name (<server>.postgres.database.azure.com).
# Server name is "${var.prefix}-${var.db_purpose}", so we append "-pdns" to differentiate.
resource "azurerm_private_dns_zone" "postgres" {
  name                = "${var.prefix}-${var.db_purpose}-pdns.postgres.database.azure.com"
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "postgres" {
  name                  = "${var.prefix}-${var.db_purpose}-vnet-link"
  private_dns_zone_name = azurerm_private_dns_zone.postgres.name
  virtual_network_id    = var.vnet.vnet_id
  resource_group_name   = var.resource_group_name
}

# ---------- Password ----------

resource "random_password" "pg_password" {
  length  = 32
  special = false
}

resource "azurerm_key_vault_secret" "pg_password" {
  name = "retool-${var.prefix}-${var.db_purpose}-db-password"
  # Write-only: not persisted in state, only (re)written when the version
  # counter changes. Bump db_password_wo_version to rotate.
  value_wo         = random_password.pg_password.result
  value_wo_version = var.db_password_wo_version
  key_vault_id     = var.vnet.key_vault_id
}

# ---------- PostgreSQL Flexible Server ----------

resource "azurerm_postgresql_flexible_server" "main" {
  name                          = "${var.prefix}-${var.db_purpose}"
  resource_group_name           = var.resource_group_name
  location                      = var.location
  version                       = var.postgres_version
  sku_name                      = var.sku_name
  administrator_login           = var.master_username
  administrator_password        = random_password.pg_password.result
  public_network_access_enabled = false
  delegated_subnet_id           = var.vnet.postgres_subnet_id
  private_dns_zone_id           = azurerm_private_dns_zone.postgres.id
  storage_mb                    = var.storage_mb
  auto_grow_enabled             = var.auto_grow_enabled
  backup_retention_days         = var.backup_retention_days
  tags                          = var.tags

  dynamic "high_availability" {
    for_each = var.high_availability_mode != "Disabled" ? [1] : []
    content {
      mode = var.high_availability_mode
    }
  }

  maintenance_window {
    day_of_week = 0
    start_hour  = 6
  }

  depends_on = [azurerm_private_dns_zone_virtual_network_link.postgres]

  lifecycle {
    ignore_changes = [
      zone,
      high_availability[0].standby_availability_zone,
    ]
  }
}

resource "azurerm_postgresql_flexible_server_database" "main" {
  name      = var.database_name
  server_id = azurerm_postgresql_flexible_server.main.id
  collation = "en_US.utf8"
  charset   = "utf8"
}

# Enable extensions required by Retool.
resource "azurerm_postgresql_flexible_server_configuration" "extensions" {
  name      = "azure.extensions"
  server_id = azurerm_postgresql_flexible_server.main.id
  value     = "UUID-OSSP,VECTOR"
}
