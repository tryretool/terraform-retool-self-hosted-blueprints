# --- Agent Sandbox secrets (gated on enable_agent_sandbox) ---

# Read the database password from Key Vault to construct the postgres URL.
data "azurerm_key_vault_secret" "db_password" {
  count        = var.enable_agent_sandbox ? 1 : 0
  name         = var.db.master_secret_name
  key_vault_id = var.vnet.key_vault_id
}

locals {
  ae_postgres_url = var.enable_agent_sandbox ? "postgresql://${var.db.username}:${urlencode(data.azurerm_key_vault_secret.db_password[0].value)}@${var.db.address}:${var.db.port}/${var.db.name}?sslmode=no-verify" : null
}

resource "tls_private_key" "agent_sandbox_jwt" {
  count       = var.enable_agent_sandbox ? 1 : 0
  algorithm   = "ECDSA"
  ecdsa_curve = "P256"
}

resource "random_bytes" "agent_sandbox_encryption_key" {
  count  = var.enable_agent_sandbox ? 1 : 0
  length = 32
}

resource "random_password" "agent_sandbox_api_secret" {
  count   = var.enable_agent_sandbox ? 1 : 0
  length  = 48
  special = false
}

resource "azurerm_key_vault_secret" "agent_sandbox" {
  count        = var.enable_agent_sandbox ? 1 : 0
  name         = "retool-${var.prefix}-agent-sandbox"
  key_vault_id = var.vnet.key_vault_id
  value = jsonencode({
    "jwt-public-key"  = tls_private_key.agent_sandbox_jwt[0].public_key_pem
    "jwt-private-key" = tls_private_key.agent_sandbox_jwt[0].private_key_pem
    "encryption-key"  = random_bytes.agent_sandbox_encryption_key[0].hex
    "api-secret"      = random_password.agent_sandbox_api_secret[0].result
    "postgres-url"    = local.ae_postgres_url
  })
}
