# Azure Storage Account and Blob container for Retool Remote Repository (RR) Git storage.
# Uses Azure Blob Storage natively via RR_GIT_AZURE_* env vars.
# Credentials are stored in Key Vault and synced to K8s via ESO.

resource "azurerm_storage_account" "rr_git" {
  count = var.enable_rr_git_blob ? 1 : 0

  # Storage account names must be 3-24 lowercase alphanumeric characters.
  name                     = replace("${var.prefix}rrgit", "-", "")
  resource_group_name      = var.resource_group_name
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = "LRS"

  allow_nested_items_to_be_public = false

  tags = var.tags
}

resource "azurerm_storage_container" "rr_git" {
  count = var.enable_rr_git_blob ? 1 : 0

  name                  = "rr-git"
  storage_account_id    = azurerm_storage_account.rr_git[0].id
  container_access_type = "private"
}

resource "azurerm_key_vault_secret" "rr_git_blob" {
  count        = var.enable_rr_git_blob ? 1 : 0
  name         = "retool-${var.prefix}-rr-git-blob"
  key_vault_id = var.vnet.key_vault_id
  value = jsonencode({
    "RR_GIT_AZURE_CONTAINER"         = azurerm_storage_container.rr_git[0].name
    "RR_GIT_AZURE_CONNECTION_STRING" = azurerm_storage_account.rr_git[0].primary_connection_string
  })
}
