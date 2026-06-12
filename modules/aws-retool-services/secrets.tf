resource "random_password" "encryption_key" {
  count   = var.encryption_key_secret_name == null ? 1 : 0
  length  = 48
  special = false
}

resource "random_password" "jwt_secret" {
  length  = 48
  special = false
}

resource "aws_secretsmanager_secret" "encryption_key" {
  count = var.encryption_key_secret_name == null ? 1 : 0
  name  = local.encryption_key_sm_path
  tags  = local.all_tags
}

resource "aws_secretsmanager_secret_version" "encryption_key" {
  count     = var.encryption_key_secret_name == null ? 1 : 0
  secret_id = aws_secretsmanager_secret.encryption_key[0].id
  # Write-only: the value is never persisted in Terraform state, and is only
  # (re)written when secret_string_wo_version changes, so out-of-band edits are
  # not reverted as drift.
  secret_string_wo         = random_password.encryption_key[0].result
  secret_string_wo_version = var.encryption_key_wo_version
}

resource "aws_secretsmanager_secret" "jwt_secret" {
  name = "retool/${var.prefix}/jwt-secret"
  tags = local.all_tags
}

resource "aws_secretsmanager_secret_version" "jwt_secret" {
  secret_id                = aws_secretsmanager_secret.jwt_secret.id
  secret_string_wo         = random_password.jwt_secret.result
  secret_string_wo_version = var.jwt_secret_wo_version
}

resource "aws_secretsmanager_secret" "extra_env_vars" {
  name = "retool/${var.prefix}/extra-env-vars"
  tags = local.all_tags
}

resource "aws_secretsmanager_secret_version" "extra_env_vars" {
  secret_id = aws_secretsmanager_secret.extra_env_vars.id
  # Seeded once with an empty JSON object. Because this is write-only, operators
  # can add keys (e.g. LICENSE_KEY) to this secret out-of-band and they will NOT
  # be reverted on the next apply. Bump extra_env_vars_wo_version to overwrite
  # the contents back to the empty object.
  secret_string_wo         = jsonencode({})
  secret_string_wo_version = var.extra_env_vars_wo_version
}

# --- Agent Sandbox secrets (gated on enable_agent_sandbox) ---

locals {
  as_postgres_url = var.enable_agent_sandbox ? "postgresql://${var.db.username}@${var.db.address}:${var.db.port}/${var.db.name}?sslmode=no-verify" : null
}

resource "tls_private_key" "agent_sandbox_jwt" {
  count       = var.enable_agent_sandbox ? 1 : 0
  algorithm   = "ECDSA"
  ecdsa_curve = "P256"
}

resource "aws_secretsmanager_secret" "agent_sandbox" {
  count = var.enable_agent_sandbox ? 1 : 0
  name  = "retool/${var.prefix}/agent-sandbox"
  tags  = local.all_tags
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

resource "aws_secretsmanager_secret_version" "agent_sandbox" {
  count     = var.enable_agent_sandbox ? 1 : 0
  secret_id = aws_secretsmanager_secret.agent_sandbox[0].id
  secret_string = jsonencode({
    "jwt-public-key"  = tls_private_key.agent_sandbox_jwt[0].public_key_pem
    "jwt-private-key" = tls_private_key.agent_sandbox_jwt[0].private_key_pem
    "encryption-key"  = random_bytes.agent_sandbox_encryption_key[0].hex
    "postgres-url"    = local.as_postgres_url
  })
}

resource "aws_secretsmanager_secret" "license_key" {
  count = nonsensitive(var.license_key != null) ? 1 : 0
  name  = "retool/${var.prefix}/license-key"
  tags  = local.all_tags
}

resource "aws_secretsmanager_secret_version" "license_key" {
  count                    = nonsensitive(var.license_key != null) ? 1 : 0
  secret_id                = aws_secretsmanager_secret.license_key[0].id
  secret_string_wo         = var.license_key
  secret_string_wo_version = var.license_key_wo_version
}
