# --- Agent Sandbox secrets (gated on enable_agent_sandbox) ---

locals {
  as_postgres_url = var.enable_agent_sandbox ? "postgresql://${var.db.username}@${var.db.address}:${var.db.port}/${var.db.name}?sslmode=no-verify" : null
}

resource "tls_private_key" "agent_sandbox_jwt" {
  count       = var.enable_agent_sandbox ? 1 : 0
  algorithm   = "ECDSA"
  ecdsa_curve = "P256"
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
  count  = var.enable_agent_sandbox ? 1 : 0
  secret = google_secret_manager_secret.agent_sandbox[0].id
  secret_data = jsonencode({
    "jwt-public-key"  = tls_private_key.agent_sandbox_jwt[0].public_key_pem
    "jwt-private-key" = tls_private_key.agent_sandbox_jwt[0].private_key_pem
    "postgres-url"    = local.as_postgres_url
  })
}

resource "google_secret_manager_secret_iam_member" "eso_agent_sandbox" {
  count     = var.enable_agent_sandbox ? 1 : 0
  project   = var.project_id
  secret_id = google_secret_manager_secret.agent_sandbox[0].secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.eso.email}"
}
