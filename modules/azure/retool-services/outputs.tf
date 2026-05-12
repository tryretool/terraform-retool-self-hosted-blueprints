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
  description = "Name of the Kubernetes Secret containing extra environment variable secrets."
  value       = "extra-env-vars"
}

output "kv_db_credentials_secret_name" {
  description = "Key Vault secret name for the database credentials (passthrough from input)."
  value       = var.db_credentials_secret_name
}

output "kv_extra_env_vars_secret_name" {
  description = "Key Vault secret name for extra environment variable secrets."
  value       = "retool-${var.prefix}-extra-env-vars"
}

output "k8s_license_key_secret_name" {
  description = "Name of the Kubernetes Secret containing the Retool license key, or null."
  value       = var.license_key != null ? "license-key" : null
  sensitive   = true
}

output "secret_store_name" {
  description = "Name of the ESO ClusterSecretStore configured for Azure Key Vault."
  value       = "azure-keyvault"
}

output "backend_type" {
  description = "ESO backend type identifier for use in Retool Helm values."
  value       = "azureKeyVault"
}
