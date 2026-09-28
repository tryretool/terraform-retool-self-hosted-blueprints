locals {
  outputs = {
    address                 = module.pg.private_ip_address
    port                    = 5432
    name                    = var.database_name
    username                = var.master_username
    id                      = module.pg.instance_name
    database_name           = var.database_name
    master_user_secret_name = google_secret_manager_secret.db_password.secret_id

    # GCP-specific: Cloud SQL Auth Proxy connection name (project:region:instance).
    connection_name = module.pg.instance_connection_name
  }
}

output "address" {
  description = "Private IP address of the Cloud SQL instance"
  value       = local.outputs.address
}

output "port" {
  description = "Port for the PostgreSQL instance (always 5432 for Cloud SQL)"
  value       = local.outputs.port
}

output "name" {
  description = "Name of the database created inside the Cloud SQL instance"
  value       = local.outputs.name
}

output "username" {
  description = "Master database username"
  value       = local.outputs.username
}

output "id" {
  description = "Name of the Cloud SQL instance"
  value       = local.outputs.id
}

output "database_name" {
  description = "Name of the database within the instance intended for primary use."
  value       = local.outputs.database_name
}

output "master_user_secret_name" {
  description = "Name of the GCP Secret Manager secret containing the database password."
  value       = local.outputs.master_user_secret_name
}

# Used to configure the Cloud SQL Auth Proxy sidecar in GKE pods.
# Format: "project:region:instance"
# Example Helm value: "--instances=<connection_name>=tcp:5432"
output "connection_name" {
  description = "Cloud SQL instance connection name (project:region:instance) for use with Cloud SQL Auth Proxy"
  value       = local.outputs.connection_name
}

output "outputs" {
  value       = local.outputs
  description = "Structured database outputs for composition with downstream modules."
}
