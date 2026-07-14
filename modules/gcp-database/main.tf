locals {
  all_labels = merge(var.default_tags, var.tags)

  # Merge var.max_connections into database_flags unless the caller already set
  # max_connections explicitly in database_flags (explicit flags take precedence).
  has_explicit_max_connections = anytrue([for f in var.database_flags : f.name == "max_connections"])
  max_connections_flag = (
    var.max_connections != null && !local.has_explicit_max_connections
    ? [{ name = "max_connections", value = tostring(var.max_connections) }]
    : []
  )
  database_flags = concat(var.database_flags, local.max_connections_flag)
}

resource "random_password" "pg_password" {
  length  = 32
  special = false
}

module "pg" {
  source  = "terraform-google-modules/sql-db/google//modules/postgresql"
  version = "25.2.2"

  name                 = "${var.prefix}-${var.db_purpose}"
  random_instance_name = true
  project_id           = var.project_id
  database_version     = var.postgres_version
  region               = var.region

  edition               = "ENTERPRISE"
  tier                  = var.tier
  disk_size             = var.disk_size_gb
  disk_autoresize       = var.disk_autoresize
  disk_autoresize_limit = var.disk_autoresize_limit_gb
  availability_type     = var.availability_type

  deletion_protection = var.deletion_protection

  # On destroy, Postgres refuses API-level DROP of the database (it has non-superuser
  # grantees) and the user (it holds SQL roles), so terraform destroy hangs. ABANDON
  # drops them from state instead; the instance deletion that follows removes them.
  database_deletion_policy = "ABANDON"
  user_deletion_policy     = "ABANDON"

  database_flags = local.database_flags

  # Cloud SQL does not use security groups. With private IP, access is controlled by
  # the VPC peering connection (private_service_access) created in the vpc module.
  # Any GKE pod in the same VPC can reach this instance on its private IP.
  #
  # GCP recommends using the Cloud SQL Auth Proxy sidecar for application connections.
  # The proxy handles TLS and IAM authentication automatically. Configure it with the
  # db_instance_connection_name output ("project:region:instance").
  ip_configuration = {
    ipv4_enabled    = false
    ssl_mode        = "ENCRYPTED_ONLY"
    private_network = var.vpc.network_id
  }

  backup_configuration = {
    enabled                        = true
    start_time                     = var.backup_start_time
    location                       = null
    point_in_time_recovery_enabled = var.point_in_time_recovery_enabled
    transaction_log_retention_days = null
    retained_backups               = var.backup_retention_count
    retention_unit                 = "COUNT"
  }

  maintenance_window_day          = var.maintenance_window_day
  maintenance_window_hour         = var.maintenance_window_hour
  maintenance_window_update_track = "stable"

  db_name      = var.database_name
  db_charset   = "UTF8"
  db_collation = "en_US.UTF8"

  user_name     = var.master_username
  user_password = random_password.pg_password.result

  user_labels = local.all_labels
}

resource "google_project_service" "secretmanager" {
  project            = var.project_id
  service            = "secretmanager.googleapis.com"
  disable_on_destroy = false
}

# Store the generated password in Secret Manager so callers (e.g. retool-services) can
# reference it by name rather than passing the plaintext value as a variable.
resource "google_secret_manager_secret" "db_password" {
  depends_on = [google_project_service.secretmanager]
  secret_id  = "${var.prefix}-${var.db_purpose}-db-password"
  project    = var.project_id

  replication {
    auto {}
  }

  labels = local.all_labels
}

resource "google_secret_manager_secret_version" "db_password" {
  secret = google_secret_manager_secret.db_password.id
  # Write-only: not persisted in state, only (re)written when the version
  # counter changes. Bump db_password_wo_version to reapply from state.
  secret_data_wo         = random_password.pg_password.result
  secret_data_wo_version = var.db_password_wo_version
}
