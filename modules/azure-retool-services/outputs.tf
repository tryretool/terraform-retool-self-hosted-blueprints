locals {
  outputs = {
    encryption_key_secret_name       = "encryption-key"
    jwt_secret_name                  = "jwt-secret"
    db_credentials_secret_name       = "db-credentials"
    db_credentials_secret_key        = "password"
    db_credentials_secret_store_path = var.db_credentials_secret_name
    extra_env_vars_secret_name       = "extra-env-vars"
    extra_env_vars_secret_path       = "retool-${var.prefix}-extra-env-vars"
    license_key_secret_name          = nonsensitive(var.license_key != null) ? "license-key" : null
    secret_store_name                = "azure-keyvault"
    backend_type                     = "azureKeyVault"
  }
}

output "encryption_key_secret_name" {
  description = "Name of the Kubernetes Secret containing the Retool encryption key."
  value       = local.outputs.encryption_key_secret_name
}

output "jwt_secret_name" {
  description = "Name of the Kubernetes Secret containing the Retool JWT secret."
  value       = local.outputs.jwt_secret_name
}

output "db_credentials_secret_name" {
  description = "Name of the Kubernetes Secret containing the database credentials."
  value       = local.outputs.db_credentials_secret_name
}

output "db_credentials_secret_key" {
  description = "Key within the db-credentials Kubernetes Secret holding the database password."
  value       = local.outputs.db_credentials_secret_key
}

output "db_credentials_secret_store_path" {
  description = "Key Vault secret name for the database credentials (passthrough from input)."
  value       = local.outputs.db_credentials_secret_store_path
}

output "extra_env_vars_secret_name" {
  description = "Name of the Kubernetes Secret containing extra environment variable secrets."
  value       = local.outputs.extra_env_vars_secret_name
}

output "extra_env_vars_secret_path" {
  description = "Key Vault secret name for extra environment variable secrets."
  value       = local.outputs.extra_env_vars_secret_path
}

output "license_key_secret_name" {
  description = "Name of the Kubernetes Secret containing the Retool license key, or null."
  value       = local.outputs.license_key_secret_name
}

output "secret_store_name" {
  description = "Name of the ESO ClusterSecretStore configured for Azure Key Vault."
  value       = local.outputs.secret_store_name
}

output "backend_type" {
  description = "ESO backend type identifier for use in Retool Helm values."
  value       = local.outputs.backend_type
}

output "outputs" {
  value       = local.outputs
  description = "Structured retool-services outputs for composition with downstream modules."
}
