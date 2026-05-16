# GCS bucket and service account for Retool Remote Repository (RR) Git storage.
# Uses native GCS client via RR_GIT_GCS_BUCKET and RR_GIT_GCS_CREDENTIALS env vars.

resource "google_storage_bucket" "rr_git" {
  count = var.enable_rr_git_gcs ? 1 : 0

  name          = "retool-${var.prefix}-rr-git"
  project       = var.project_id
  location      = var.region
  force_destroy = true

  uniform_bucket_level_access = true

  labels = local.all_labels
}

resource "google_service_account" "rr_git" {
  count = var.enable_rr_git_gcs ? 1 : 0

  account_id   = "${var.prefix}-rr-git"
  display_name = "${var.prefix} RR Git storage service account"
  project      = var.project_id
}

resource "google_storage_bucket_iam_member" "rr_git" {
  count = var.enable_rr_git_gcs ? 1 : 0

  bucket = google_storage_bucket.rr_git[0].name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.rr_git[0].email}"
}

resource "google_service_account_key" "rr_git" {
  count = var.enable_rr_git_gcs ? 1 : 0

  service_account_id = google_service_account.rr_git[0].name
}

# Store the SA key JSON and bucket name in Secret Manager so ESO can sync them
# to a K8s Secret. This keeps credentials out of the Terraform state at rest.
resource "google_secret_manager_secret" "rr_git_gcs" {
  count     = var.enable_rr_git_gcs ? 1 : 0
  secret_id = "retool-${var.prefix}-rr-git-gcs"
  project   = var.project_id

  replication {
    auto {}
  }

  labels     = local.all_labels
  depends_on = [google_project_service.secretmanager]
}

resource "google_secret_manager_secret_version" "rr_git_gcs" {
  count  = var.enable_rr_git_gcs ? 1 : 0
  secret = google_secret_manager_secret.rr_git_gcs[0].id
  secret_data = jsonencode({
    RR_BLOB_STORAGE_PROVIDER = "gcs"
    RR_GIT_GCS_BUCKET        = google_storage_bucket.rr_git[0].name
    RR_GIT_GCS_CREDENTIALS   = base64decode(google_service_account_key.rr_git[0].private_key)
  })
}

resource "google_secret_manager_secret_iam_member" "eso_rr_git_gcs" {
  count     = var.enable_rr_git_gcs ? 1 : 0
  project   = var.project_id
  secret_id = google_secret_manager_secret.rr_git_gcs[0].secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.eso.email}"
}
