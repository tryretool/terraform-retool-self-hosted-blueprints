# --- Agent Sandbox secrets (gated on enable_agent_sandbox) ---

locals {
  as_postgres_url = var.enable_agent_sandbox ? "postgresql://${var.db.username}@${var.db.address}:${var.db.port}/${var.db.name}?sslmode=no-verify" : null
}

resource "tls_private_key" "agent_sandbox_jwt" {
  count       = var.enable_agent_sandbox ? 1 : 0
  algorithm   = "ECDSA"
  ecdsa_curve = "P256"
}

resource "azurerm_key_vault_secret" "agent_sandbox" {
  count        = var.enable_agent_sandbox ? 1 : 0
  name         = "retool-${var.prefix}-agent-sandbox"
  key_vault_id = var.vnet.key_vault_id
  value = jsonencode({
    "jwt-public-key"  = tls_private_key.agent_sandbox_jwt[0].public_key_pem
    "jwt-private-key" = tls_private_key.agent_sandbox_jwt[0].private_key_pem
    "postgres-url"    = local.as_postgres_url
  })
}
