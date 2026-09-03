locals {
  outputs = {
    retool_namespace                 = local.retool_namespace
    eso_identity_client_id           = azurerm_user_assigned_identity.eso.client_id
    eso_identity_principal_id        = azurerm_user_assigned_identity.eso.principal_id
    encryption_key_secret_name       = "encryption-key"
    jwt_secret_name                  = "jwt-secret"
    db_credentials_secret_name       = "db-credentials"
    db_credentials_secret_key        = "password"
    db_credentials_secret_store_path = var.db.master_secret_name
    extra_env_vars_secret_name       = "extra-env-vars"
    extra_env_vars_secret_path       = "retool-${var.prefix}-extra-env-vars"
    license_key_secret_name          = (nonsensitive(var.license_key != null) || var.license_key_secret_path != null) ? "license-key" : null
    license_key_secret_key           = (nonsensitive(var.license_key != null) || var.license_key_secret_path != null) ? "license-key" : null
    agent_sandbox_enabled            = var.enable_agent_sandbox
    agent_sandbox_secret_name        = var.enable_agent_sandbox ? "agent-sandbox" : null
    rr_bucket_k8s_secret_name        = var.enable_rr_blob ? "rr-blob-credentials" : null
    rr_bucket_env_keys               = var.enable_rr_blob ? ["RR_DEFAULT_AZURE_CONTAINER", "RR_DEFAULT_AZURE_CONNECTION_STRING", "RR_BLOB_STORAGE_PROVIDER"] : []
    secret_store_name                = local.secret_store_name
    secret_store_kind                = local.secret_store_kind
    secret_store_backend_type        = "azureKeyVault"
  }
}

output "retool_namespace" {
  description = "Namespace the Retool application and its Secrets are deployed into. Pass to retool-helm (via retool_services) and to the user-ingress module."
  value       = local.outputs.retool_namespace
}

output "secret_store_kind" {
  description = "Kind of the ESO secret store (SecretStore, namespaced)."
  value       = local.outputs.secret_store_kind
}

output "eso_identity_client_id" {
  description = "Client ID of the managed identity ESO uses to read Key Vault. In a shared cluster (enable_external_secrets = false), federate the platform ESO's service account to this identity (or grant its identity the same Key Vault access)."
  value       = local.outputs.eso_identity_client_id
}

output "eso_identity_principal_id" {
  description = "Principal ID of the managed identity ESO uses to read Key Vault."
  value       = local.outputs.eso_identity_principal_id
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

output "license_key_secret_key" {
  description = "Key within the license-key Kubernetes Secret holding the license key, or null if no key was provided."
  value       = local.outputs.license_key_secret_key
}

output "agent_sandbox_enabled" {
  description = "Whether agent sandbox was enabled in this retool-services deployment."
  value       = local.outputs.agent_sandbox_enabled
}

output "agent_sandbox_secret_name" {
  description = "Name of the Kubernetes Secret containing agent sandbox credentials, or null when agent sandbox is disabled."
  value       = local.outputs.agent_sandbox_secret_name
}

output "rr_bucket_k8s_secret_name" {
  description = "Name of the K8s Secret for Remote Repository bucket credentials. Null when enable_rr_blob is false."
  value       = local.outputs.rr_bucket_k8s_secret_name
}

output "rr_bucket_env_keys" {
  description = "Env var keys stored in the RR bucket K8s Secret. Empty when enable_rr_blob is false."
  value       = local.outputs.rr_bucket_env_keys
}

output "secret_store_name" {
  description = "Name of the ESO ClusterSecretStore configured for Azure Key Vault."
  value       = local.outputs.secret_store_name
}

output "secret_store_backend_type" {
  description = "ESO secret store backend type identifier for use in Retool Helm values."
  value       = local.outputs.secret_store_backend_type
}

output "outputs" {
  value       = local.outputs
  description = "Structured retool-services outputs for composition with downstream modules."
}
