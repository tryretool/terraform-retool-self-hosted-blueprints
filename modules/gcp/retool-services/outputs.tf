output "k8s_encryption_key_secret_name" {
  description = "Name of the Kubernetes Secret containing the Retool encryption key."
  value       = "encryption-key"
}

output "k8s_jwt_secret_name" {
  description = "Name of the Kubernetes Secret containing the Retool JWT secret."
  value       = "jwt-secret"
}

output "k8s_db_credentials_secret_name" {
  description = "Name of the Kubernetes Secret containing the database credentials."
  value       = "db-credentials"
}

output "k8s_db_credentials_secret_key" {
  description = "Key within the db-credentials Kubernetes Secret holding the database password."
  value       = "password"
}

output "k8s_extra_env_vars_secret_name" {
  description = "Name of the Kubernetes Secret containing extra environment variable secrets for Retool workloads."
  value       = "extra-env-vars"
}

output "sm_db_credentials_secret_name" {
  description = "GCP Secret Manager secret name for the database credentials (passed through from var.db_credentials_secret_name)."
  value       = var.db_credentials_secret_name
}

output "sm_extra_env_vars_secret_name" {
  description = "GCP Secret Manager secret name for extra environment variable secrets."
  value       = "retool-${var.prefix}-extra-env-vars"
}

output "secret_store_name" {
  description = "Name of the ESO ClusterSecretStore configured for GCP Secret Manager."
  value       = "gcp-secretsmanager"
}

output "backend_type" {
  description = "ESO backend type identifier for use in Retool Helm values."
  value       = "gcpSecretsManager"
}
