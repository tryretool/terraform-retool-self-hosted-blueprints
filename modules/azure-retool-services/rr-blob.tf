# Azure Storage Account and Blob container for Retool Remote Repository (RR) storage.
# Uses Azure Blob Storage natively via RR_DEFAULT_AZURE_* env vars.
# Credentials are stored in Key Vault and synced to K8s via ESO.

resource "azurerm_storage_account" "rr" {
  count = var.enable_rr_blob ? 1 : 0

  # Storage account names must be 3-24 lowercase alphanumeric characters.
  name                     = replace("${var.prefix}rr", "-", "")
  resource_group_name      = var.resource_group_name
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = "LRS"

  allow_nested_items_to_be_public = false

  tags = var.tags
}

resource "azurerm_storage_container" "rr" {
  count = var.enable_rr_blob ? 1 : 0

  name                  = "rr-blob"
  storage_account_id    = azurerm_storage_account.rr[0].id
  container_access_type = "private"
}

resource "azurerm_key_vault_secret" "rr_blob" {
  count        = var.enable_rr_blob ? 1 : 0
  name         = "retool-${var.prefix}-rr-blob"
  key_vault_id = var.vnet.key_vault_id
  value = jsonencode({
    "RR_BLOB_STORAGE_PROVIDER"           = "azure"
    "RR_DEFAULT_AZURE_CONTAINER"         = azurerm_storage_container.rr[0].name
    "RR_DEFAULT_AZURE_CONNECTION_STRING" = azurerm_storage_account.rr[0].primary_connection_string
  })
}
