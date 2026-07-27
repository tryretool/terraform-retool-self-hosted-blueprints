locals {
  all_labels = merge(var.default_tags, var.tags)
}

resource "google_project_service" "secretmanager" {
  project            = var.project_id
  service            = "secretmanager.googleapis.com"
  disable_on_destroy = false
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

resource "google_secret_manager_secret" "encryption_key" {
  count     = var.encryption_key_secret_name == null ? 1 : 0
  secret_id = "retool-${var.prefix}-encryption-key"
  project   = var.project_id

  replication {
    auto {}
  }

  labels     = local.all_labels
  depends_on = [google_project_service.secretmanager]
}

resource "google_secret_manager_secret_version" "encryption_key" {
  count       = var.encryption_key_secret_name == null ? 1 : 0
  secret      = google_secret_manager_secret.encryption_key[0].id
  secret_data = random_password.encryption_key[0].result

  # Seed once. ignore_changes hands the value off to admins: rotations made
  # directly in Secret Manager are not reverted as drift on later applies.
  lifecycle {
    ignore_changes = [secret_data]
  }
}

resource "google_secret_manager_secret" "jwt_secret" {
  secret_id = "retool-${var.prefix}-jwt-secret"
  project   = var.project_id

  replication {
    auto {}
  }

  labels     = local.all_labels
  depends_on = [google_project_service.secretmanager]
}

resource "google_secret_manager_secret_version" "jwt_secret" {
  secret      = google_secret_manager_secret.jwt_secret.id
  secret_data = random_password.jwt_secret.result

  # Seed once. ignore_changes hands the value off to admins: rotations made
  # directly in Secret Manager are not reverted as drift on later applies.
  lifecycle {
    ignore_changes = [secret_data]
  }
}

resource "google_secret_manager_secret" "extra_env_vars" {
  secret_id = "retool-${var.prefix}-extra-env-vars"
  project   = var.project_id

  replication {
    auto {}
  }

  labels     = local.all_labels
  depends_on = [google_project_service.secretmanager]
}

resource "google_secret_manager_secret_version" "extra_env_vars" {
  secret = google_secret_manager_secret.extra_env_vars.id
  # Seeded once with an empty JSON object. ignore_changes lets operators add keys
  # (e.g. LICENSE_KEY) out-of-band without Terraform reverting them on later applies.
  secret_data = jsonencode({})

  lifecycle {
    ignore_changes = [secret_data]
  }
}

# --- License Key (gated on license_key != null) ---

resource "google_secret_manager_secret" "license_key" {
  count     = nonsensitive(var.license_key != null) ? 1 : 0
  secret_id = "retool-${var.prefix}-license-key"
  project   = var.project_id

  replication {
    auto {}
  }

  labels     = local.all_labels
  depends_on = [google_project_service.secretmanager]
}

resource "google_secret_manager_secret_version" "license_key" {
  count       = nonsensitive(var.license_key != null) ? 1 : 0
  secret      = google_secret_manager_secret.license_key[0].id
  secret_data = var.license_key

  # Seed once. ignore_changes hands the value off to admins: rotations made
  # directly in Secret Manager are not reverted as drift on later applies.
  lifecycle {
    ignore_changes = [secret_data]
  }
}
