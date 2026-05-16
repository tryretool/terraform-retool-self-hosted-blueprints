locals {
  outputs = {
    encryption_key_secret_name       = "encryption-key"
    jwt_secret_name                  = "jwt-secret"
    db_credentials_secret_name       = "db-credentials"
    db_credentials_secret_key        = "password"
    db_credentials_secret_store_path = var.db.master_secret_name
    extra_env_vars_secret_name       = "extra-env-vars"
    extra_env_vars_secret_path       = "retool-${var.prefix}-extra-env-vars"
    license_key_secret_name          = nonsensitive(var.license_key != null) ? "license-key" : null
    agent_sandbox_secret_name        = var.enable_agent_sandbox ? "agent-sandbox" : null
    rr_git_bucket_k8s_secret_name    = var.enable_rr_git_blob ? "rr-git-blob-credentials" : null
    rr_git_bucket_env_keys           = var.enable_rr_git_blob ? ["RR_GIT_AZURE_CONTAINER", "RR_GIT_AZURE_CONNECTION_STRING", "RR_BLOB_STORAGE_PROVIDER"] : []
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

output "agent_sandbox_secret_name" {
  description = "Name of the Kubernetes Secret containing agent sandbox credentials, or null when agent sandbox is disabled."
  value       = local.outputs.agent_sandbox_secret_name
}

output "rr_git_bucket_k8s_secret_name" {
  description = "Name of the K8s Secret for Remote Repository Git bucket credentials. Null when enable_rr_git_blob is false."
  value       = local.outputs.rr_git_bucket_k8s_secret_name
}

output "rr_git_bucket_env_keys" {
  description = "Env var keys stored in the RR Git bucket K8s Secret. Empty when enable_rr_git_blob is false."
  value       = local.outputs.rr_git_bucket_env_keys
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
