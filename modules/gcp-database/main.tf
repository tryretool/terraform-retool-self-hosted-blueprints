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

# Matches terraform-google-modules/sql-db postgresql random_instance_name suffix.
resource "random_id" "instance_suffix" {
  byte_length = 4
}

moved {
  from = module.pg.random_id.suffix[0]
  to   = random_id.instance_suffix
}

locals {
  instance_name = "${var.prefix}-${var.db_purpose}-${random_id.instance_suffix.hex}"
  instance_body = {
    region           = var.region
    databaseVersion  = var.postgres_version
    settings = {
      tier                       = var.tier
      edition                    = "ENTERPRISE"
      dataDiskSizeGb             = tostring(var.disk_size_gb)
      storageAutoResize          = var.disk_autoresize
      storageAutoResizeLimit     = tostring(var.disk_autoresize_limit_gb)
      availabilityType           = var.availability_type
      deletionProtectionEnabled  = var.deletion_protection
      userLabels                 = local.all_labels
      databaseFlags              = [for f in local.database_flags : { name = f.name, value = f.value }]
      ipConfiguration = merge(
        {
          ipv4Enabled    = false
          sslMode        = "ENCRYPTED_ONLY"
          privateNetwork = var.vpc.network_id
        },
        coalesce(try(var.vpc.psa_allocated_ip_range, null), "") != "" ? { allocatedIpRange = var.vpc.psa_allocated_ip_range } : {}
      )
      backupConfiguration = {
        enabled                     = true
        startTime                   = var.backup_start_time
        pointInTimeRecoveryEnabled  = var.point_in_time_recovery_enabled
        backupRetentionSettings = {
          retainedBackups = var.backup_retention_count
          retentionUnit   = "COUNT"
        }
      }
      maintenanceWindow = {
        day         = var.maintenance_window_day
        hour        = var.maintenance_window_hour
        updateTrack = "stable"
      }
    }
  }
}

data "google_client_config" "default" {}

# Cloud SQL takes its private IP from the peering range that private_service_access
# sets up, and that range is not usable the moment the peering resource returns.
resource "time_sleep" "psa_propagation" {
  create_duration = "90s"

  triggers = {
    network_id = var.vpc.network_id
  }
}

# The google provider treats a still-RUNNING SQL operation with INTERNAL_ERROR as
# fatal and prints an empty "Error waiting for Create Instance:", while GCP keeps
# building the instance. Creating via the SQL Admin API lets us keep polling.
resource "null_resource" "sql_instance" {
  depends_on = [time_sleep.psa_propagation]

  triggers = {
    project   = var.project_id
    name      = local.instance_name
    body_hash = sha256(jsonencode(local.instance_body))
  }

  provisioner "local-exec" {
    command = "sh -c 'PY=$(command -v python3 || command -v python); exec \"$PY\" \"${path.module}/scripts/cloud_sql_instance.py\" upsert'"
    environment = {
      SQL_PROJECT = var.project_id
      SQL_NAME    = local.instance_name
      SQL_BODY    = jsonencode(local.instance_body)
      SQL_TOKEN   = data.google_client_config.default.access_token
    }
  }

  provisioner "local-exec" {
    when    = destroy
    command = "sh -c 'PY=$(command -v python3 || command -v python); exec \"$PY\" \"${path.module}/scripts/cloud_sql_instance.py\" delete'"
    environment = {
      SQL_PROJECT = self.triggers.project
      SQL_NAME    = self.triggers.name
    }
  }
}

data "google_sql_database_instance" "pg" {
  project    = var.project_id
  name       = local.instance_name
  depends_on = [null_resource.sql_instance]
}

# On destroy, Postgres refuses API-level DROP of the database (it has non-superuser
# grantees) and the user (it holds SQL roles), so terraform destroy hangs. ABANDON
# drops them from state instead; the instance deletion that follows removes them.
resource "google_sql_database" "retool" {
  project           = var.project_id
  name              = var.database_name
  instance          = local.instance_name
  charset           = "UTF8"
  collation         = "en_US.UTF8"
  deletion_policy   = "ABANDON"
  depends_on        = [null_resource.sql_instance]
}

resource "google_sql_user" "retool" {
  project         = var.project_id
  name            = var.master_username
  instance        = local.instance_name
  password        = random_password.pg_password.result
  deletion_policy = "ABANDON"
  depends_on      = [null_resource.sql_instance]
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
