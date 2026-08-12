locals {
  outputs = {
    retool_namespace                 = local.retool_namespace
    services_namespace               = local.services_namespace
    secret_store_name                = local.secret_store_name
    secret_store_kind                = local.secret_store_kind
    encryption_key_secret_name       = "encryption-key"
    jwt_secret_name                  = "jwt-secret"
    db_credentials_secret_name       = "db-credentials"
    db_credentials_secret_key        = "password"
    db_credentials_secret_store_path = var.db.master_user_secret_arn
    extra_env_vars_secret_name       = "extra-env-vars"
    extra_env_vars_secret_path       = "retool/${var.prefix}/extra-env-vars"
    license_key_secret_name          = (nonsensitive(var.license_key != null) || var.license_key_secret_path != null) ? "license-key" : null
    license_key_secret_key           = (nonsensitive(var.license_key != null) || var.license_key_secret_path != null) ? "license-key" : null
    agent_sandbox_enabled            = var.enable_agent_sandbox
    agent_sandbox_secret_name        = var.enable_agent_sandbox ? "agent-sandbox" : null
    rr_bucket_k8s_secret_name        = var.enable_rr_s3 ? "rr-s3-credentials" : null
    rr_bucket_env_keys = [
      "RR_DEFAULT_S3_BUCKET",
      "RR_DEFAULT_S3_REGION",
      "RR_DEFAULT_S3_ACCESS_KEY_ID",
      "RR_DEFAULT_S3_SECRET_ACCESS_KEY",
    ]
    secret_store_backend_type     = "secretsManager"
    alb_controller_irsa_role_arn  = var.enable_alb_controller ? module.alb_controller_irsa_role[0].iam_role_arn : null
    alb_controller_irsa_role_name = var.enable_alb_controller ? module.alb_controller_irsa_role[0].iam_role_name : null
    eso_irsa_role_arn             = aws_iam_role.eso.arn
  }
}

output "retool_namespace" {
  description = "Namespace the Retool application and its Secrets are deployed into. Pass to retool-helm (via retool_services) and to the user-ingress module."
  value       = local.outputs.retool_namespace
}

output "services_namespace" {
  description = "Namespace the supporting operators (ESO, reloader, cert-manager, ALB controller) are deployed into."
  value       = local.outputs.services_namespace
}

output "secret_store_name" {
  description = "Name of the namespaced ESO SecretStore in the retool namespace."
  value       = local.outputs.secret_store_name
}

output "secret_store_kind" {
  description = "Kind of the ESO secret store (SecretStore, namespaced)."
  value       = local.outputs.secret_store_kind
}

output "eso_irsa_role_arn" {
  description = "ARN of the IAM role granting Secrets Manager read access for the External Secrets Operator. In a shared cluster (enable_external_secrets = false), attach this to the platform ESO's service account."
  value       = local.outputs.eso_irsa_role_arn
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
  description = "ARN/path of the secret store entry holding the database credentials."
  value       = local.outputs.db_credentials_secret_store_path
}

output "extra_env_vars_secret_name" {
  description = "Name of the Kubernetes Secret containing extra environment variable secrets for Retool workloads."
  value       = local.outputs.extra_env_vars_secret_name
}

output "extra_env_vars_secret_path" {
  description = "Secrets Manager secret path for extra environment variable secrets."
  value       = local.outputs.extra_env_vars_secret_path
}

output "license_key_secret_name" {
  description = "Name of the Kubernetes Secret containing the Retool license key, or null if no key was provided."
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
  description = "Name of the K8s Secret for Remote Repository S3 credentials. Null when enable_rr_s3 is false."
  value       = local.outputs.rr_bucket_k8s_secret_name
}

output "secret_store_backend_type" {
  description = "ESO secret store backend type identifier for use in Retool Helm values."
  value       = local.outputs.secret_store_backend_type
}

output "alb_controller_irsa_role_arn" {
  description = "ARN of the IAM role used by the ALB controller (IRSA)."
  value       = local.outputs.alb_controller_irsa_role_arn
}

output "alb_controller_irsa_role_name" {
  description = "Name of the IAM role used by the ALB controller (IRSA)."
  value       = local.outputs.alb_controller_irsa_role_name
}

output "outputs" {
  value       = local.outputs
  description = "Structured retool-services outputs for composition with downstream modules."
}
