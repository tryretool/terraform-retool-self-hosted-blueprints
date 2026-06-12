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
  count = var.encryption_key_secret_name == null ? 1 : 0
  name  = "retool-${var.prefix}-encryption-key"
  # Write-only: the value is never persisted in Terraform state, and is only
  # (re)written when value_wo_version changes, so out-of-band edits are not
  # reverted as drift.
  value_wo         = random_password.encryption_key[0].result
  value_wo_version = var.encryption_key_wo_version
  key_vault_id     = var.vnet.key_vault_id
}

resource "azurerm_key_vault_secret" "jwt_secret" {
  name             = "retool-${var.prefix}-jwt-secret"
  value_wo         = random_password.jwt_secret.result
  value_wo_version = var.jwt_secret_wo_version
  key_vault_id     = var.vnet.key_vault_id
}

resource "azurerm_key_vault_secret" "extra_env_vars" {
  name = "retool-${var.prefix}-extra-env-vars"
  # Seeded once with an empty JSON object. Because this is write-only, operators
  # can add keys (e.g. LICENSE_KEY) to this secret out-of-band and they will NOT
  # be reverted on the next apply. Bump extra_env_vars_wo_version to overwrite
  # the contents back to the empty object.
  value_wo         = jsonencode({})
  value_wo_version = var.extra_env_vars_wo_version
  key_vault_id     = var.vnet.key_vault_id
}

resource "azurerm_key_vault_secret" "license_key" {
  count            = var.license_key != null ? 1 : 0
  name             = "retool-${var.prefix}-license-key"
  value_wo         = var.license_key
  value_wo_version = var.license_key_wo_version
  key_vault_id     = var.vnet.key_vault_id
}
