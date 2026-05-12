# ---------- Secret generation ----------
# Mirrors the GCP pattern: generate random values for encryption key, JWT secret,
# and an empty JSON object for extra-env-vars, then store them in Key Vault.

locals {
  encryption_key_secret_ref = (
    var.encryption_key_secret_name != null
    ? var.encryption_key_secret_name
    : "retool-${var.prefix}-encryption-key"
  )
}

resource "random_password" "encryption_key" {
  count   = var.encryption_key_secret_name == null ? 1 : 0
  length  = 48
  special = false
}

resource "random_password" "jwt_secret" {
  length  = 48
  special = false
}

resource "azurerm_key_vault_secret" "encryption_key" {
  count        = var.encryption_key_secret_name == null ? 1 : 0
  name         = "retool-${var.prefix}-encryption-key"
  value        = random_password.encryption_key[0].result
  key_vault_id = var.key_vault_id
}

resource "azurerm_key_vault_secret" "jwt_secret" {
  name         = "retool-${var.prefix}-jwt-secret"
  value        = random_password.jwt_secret.result
  key_vault_id = var.key_vault_id
}

resource "azurerm_key_vault_secret" "extra_env_vars" {
  name         = "retool-${var.prefix}-extra-env-vars"
  value        = jsonencode({})
  key_vault_id = var.key_vault_id
}

resource "azurerm_key_vault_secret" "license_key" {
  count        = var.license_key != null ? 1 : 0
  name         = "retool-${var.prefix}-license-key"
  value        = var.license_key
  key_vault_id = var.key_vault_id
}
