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

# Cloud SQL takes its private IP from the peering range that private_service_access
# sets up, and that range is not usable the moment the peering resource returns.
# Callers order this module after the VPC (the marketplace root uses depends_on), so
# with no wait the instance create fires a fraction of a second after peering and the
# create operation comes back with a transient INTERNAL_ERROR. The provider prints that
# as an empty "Error waiting for Create Instance:" and never retries, so the apply fails
# while GCP goes on to build the instance. Cleaning that up means deleting an orphan
# whose name Cloud SQL then reserves for a week, which costs far more than the wait.
resource "time_sleep" "psa_propagation" {
  create_duration = "90s"

  triggers = {
    network_id = var.vpc.network_id
  }
}

module "pg" {
  source  = "terraform-google-modules/sql-db/google//modules/postgresql"
  version = "25.2.2"

  module_depends_on = [time_sleep.psa_propagation.id]

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
  secret      = google_secret_manager_secret.db_password.id
  secret_data = random_password.pg_password.result

  # Seed once. ignore_changes hands the value off to admins: rotations made
  # directly in Secret Manager are not reverted as drift on later applies.
  lifecycle {
    ignore_changes = [secret_data]
  }
}
