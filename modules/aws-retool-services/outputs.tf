locals {
  outputs = {
    encryption_key_secret_name       = "encryption-key"
    jwt_secret_name                  = "jwt-secret"
    db_credentials_secret_name       = "db-credentials"
    db_credentials_secret_key        = "password"
    db_credentials_secret_store_path = var.db.master_user_secret_arn
    extra_env_vars_secret_name       = "extra-env-vars"
    extra_env_vars_secret_path       = "retool/${var.prefix}/extra-env-vars"
    license_key_secret_name          = nonsensitive(var.license_key != null) ? "license-key" : null
    agent_sandbox_secret_name        = var.enable_agent_sandbox ? "agent-sandbox" : null
    rr_git_bucket_k8s_secret_name    = var.enable_rr_git_s3 ? "rr-git-s3-credentials" : null
    rr_git_bucket_env_keys           = ["RR_GIT_S3_BUCKET", "RR_GIT_S3_REGION", "RR_GIT_S3_ACCESS_KEY_ID", "RR_GIT_S3_SECRET_ACCESS_KEY"]
    alb_controller_irsa_role_arn     = module.alb_controller_irsa_role.iam_role_arn
    alb_controller_irsa_role_name    = module.alb_controller_irsa_role.iam_role_name
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

output "agent_sandbox_secret_name" {
  description = "Name of the Kubernetes Secret containing agent sandbox credentials, or null when agent sandbox is disabled."
  value       = local.outputs.agent_sandbox_secret_name
}

output "rr_git_bucket_k8s_secret_name" {
  description = "Name of the K8s Secret for Remote Repository Git S3 credentials. Null when enable_rr_git_s3 is false."
  value       = local.outputs.rr_git_bucket_k8s_secret_name
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
