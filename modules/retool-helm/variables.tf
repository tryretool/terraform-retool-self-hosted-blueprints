variable "retool_helm_name" {
  type        = string
  description = "Name for Retool Helm release"
  default     = "retool"
}

variable "retool_helm_extra_values" {
  type        = list(string)
  description = "List of Helm values files contents. Each list element should be a YAML string conforming to the [Retool Helm chart values.yaml schema](https://github.com/retool/helm-charts/blob/main/charts/retool/values.yaml)."
  default     = []
}

variable "retool_helm_chart_version" {
  type        = string
  description = "Version of Retool Helm chart to deploy"
  default     = "6.10.0"
}

variable "retool_helm_chart_use_unpublished_branch" {
  type        = string
  description = "When present, use the given github branch name (or git ref) instead of the official chart repo. Requires the [`helm-git`](https://github.com/aslafy-z/helm-git) plugin to be installed locally."
  default     = null
}

variable "db" {
  type = object({
    address  = string
    port     = number
    name     = string
    username = string
  })
  default     = null
  description = "Database connection details (e.g. from module.db-main outputs). When set alongside retool_services, configures Retool helm config.postgresql.*."
}

variable "retool_services" {
  type = object({
    encryption_key_secret_name       = string
    jwt_secret_name                  = string
    db_credentials_secret_name       = string
    db_credentials_secret_key        = string
    db_credentials_secret_store_path = string
    extra_env_vars_secret_name       = string
    extra_env_vars_secret_path       = string
    license_key_secret_name          = optional(string)
    rr_git_s3_k8s_secret_name        = optional(string)
    secret_store_name                = optional(string, "aws-secretsmanager")
    backend_type                     = optional(string, "secretsManager")
  })
  default     = null
  description = "K8s Secret names and cloud secret store paths from the retool-services module (e.g. module.retool-services.outputs). When set alongside db, configures Retool helm config.encryptionKeySecretName, jwtSecretSecretName, config.postgresql.passwordSecretRef, and externalSecrets."
}
