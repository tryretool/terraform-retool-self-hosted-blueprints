# --- Agent Sandbox secrets (gated on enable_agent_sandbox) ---

# Read the database password from Secret Manager to construct the postgres URL.
data "google_secret_manager_secret_version" "db_password" {
  count   = var.enable_agent_sandbox ? 1 : 0
  secret  = var.db.master_user_secret_name
  project = var.project_id
}

locals {
  ae_postgres_url = var.enable_agent_sandbox ? "postgresql://${var.db.username}:${urlencode(data.google_secret_manager_secret_version.db_password[0].secret_data)}@${var.db.address}:${var.db.port}/${var.db.name}?sslmode=no-verify" : null
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

resource "google_secret_manager_secret" "agent_sandbox" {
  count     = var.enable_agent_sandbox ? 1 : 0
  secret_id = "retool-${var.prefix}-agent-sandbox"
  project   = var.project_id

  replication {
    auto {}
  }

  labels     = local.all_labels
  depends_on = [google_project_service.secretmanager]
}

resource "google_secret_manager_secret_version" "agent_sandbox" {
  count     = var.enable_agent_sandbox ? 1 : 0
  secret    = google_secret_manager_secret.agent_sandbox[0].id
  secret_data = jsonencode({
    "jwt-public-key"  = tls_private_key.agent_sandbox_jwt[0].public_key_pem
    "jwt-private-key" = tls_private_key.agent_sandbox_jwt[0].private_key_pem
    "encryption-key"  = random_bytes.agent_sandbox_encryption_key[0].hex
    "api-secret"      = random_password.agent_sandbox_api_secret[0].result
    "postgres-url"    = local.ae_postgres_url
  })
}

resource "google_secret_manager_secret_iam_member" "eso_agent_sandbox" {
  count     = var.enable_agent_sandbox ? 1 : 0
  project   = var.project_id
  secret_id = google_secret_manager_secret.agent_sandbox[0].secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.eso.email}"
}
