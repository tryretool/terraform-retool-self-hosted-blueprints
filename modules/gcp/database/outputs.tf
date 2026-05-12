output "db_name" {
  description = "Name of the database created inside the Cloud SQL instance"
  value       = var.database_name
}

output "db_instance_address" {
  description = "Private IP address of the Cloud SQL instance"
  value       = module.pg.private_ip_address
}

output "db_instance_port" {
  description = "Port for the PostgreSQL instance (always 5432 for Cloud SQL)"
  value       = 5432
}

output "db_instance_name" {
  description = "Name of the Cloud SQL instance"
  value       = module.pg.instance_name
}

# Used to configure the Cloud SQL Auth Proxy sidecar in GKE pods.
# Format: "project:region:instance"
# Example Helm value: "--instances=<connection_name>=tcp:5432"
output "db_instance_connection_name" {
  description = "Cloud SQL instance connection name (project:region:instance) for use with Cloud SQL Auth Proxy"
  value       = module.pg.instance_connection_name
}

output "db_instance_username" {
  description = "Master database username"
  value       = var.master_username
}

output "db_instance_database_name" {
  description = "Name of the database within the instance intended for primary use."
  value       = var.database_name
}

output "db_instance_master_user_secret_name" {
  description = "Name of the GCP Secret Manager secret containing the database password."
  value       = google_secret_manager_secret.db_password.secret_id
}
