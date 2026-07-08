variable "retool_helm_name" {
  type        = string
  description = "Name for Retool Helm release"
  default     = "retool"
}

variable "retool_helm_extra_values" {
  type        = list(string)
  description = "List of Helm values files contents. Each list element should be a YAML string conforming to the [Retool Helm chart values.yaml schema](https://github.com/tryretool/retool-helm/blob/main/charts/retool/values.yaml)."
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

variable "retool_helm_chart_repository" {
  type        = string
  description = "Overrides the chart repository. Takes precedence over retool_helm_chart_use_unpublished_branch. Leave null to use the published chart."
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
    license_key_secret_key           = optional(string)
    agent_sandbox_enabled            = optional(bool, false)
    agent_sandbox_secret_name        = optional(string)
    rr_bucket_k8s_secret_name        = optional(string)
    rr_bucket_env_keys               = optional(list(string), [])
    secret_store_name                = optional(string, "aws-secretsmanager")
    backend_type                     = optional(string, "secretsManager")
  })
  default     = null
  description = "K8s Secret names and cloud secret store paths from the retool-services module (e.g. module.retool-services.outputs). When set alongside db, configures Retool helm config.encryptionKeySecretName, jwtSecretSecretName, config.postgresql.passwordSecretRef, and externalSecrets. When agent_sandbox_enabled is true, agentSandbox.enabled, agentSandbox.postgres.schema, and jsExecutor.enabled are configured automatically."
}

variable "user_ingress" {
  type = object({
    ingress_mode         = optional(string)
    gateway_name         = optional(string)
    gateway_section_name = optional(string)
    ingress_class_name   = optional(string)
    cluster_issuer_name  = optional(string)
    tls_secret_name      = optional(string)
  })
  default     = null
  description = "User-ingress outputs (e.g. module.user-ingress.outputs) describing how end-user traffic reaches the cluster. ingress_mode (\"targetGroupBinding\", \"httpRoute\", or \"ingress\") selects which Helm values block (ingress.* / httpRoute.* / agentSandbox.proxy.ingress.*) to render."
}

variable "domain_name" {
  type        = string
  default     = null
  description = "External domain that serves Retool to end users (e.g. \"retool.example.com\"). When set, configures env.BASE_DOMAIN, agentSandbox.frontendWsProxyDomain, agentSandbox.proxy.backendDomainSuffixes, and config.useInsecureCookies. The URL scheme is selected by https_enabled."
}

variable "https_enabled" {
  type        = bool
  default     = true
  description = "Whether the user-facing ingress terminates HTTPS. Drives the scheme used in BASE_DOMAIN / frontendWsProxyDomain and inverts config.useInsecureCookies (cookies are only marked Secure when HTTPS is in use)."
}

variable "workflows_enabled" {
  type        = bool
  default     = true
  description = "Whether to enable the Workflows service in the Retool deployment."
}

variable "dbconnector_enabled" {
  type        = bool
  default     = true
  description = "Whether to enable the dbconnector service in the Retool deployment."
}
