variable "prefix" {
  type        = string
  description = "Prefix for resource names."
}

variable "region" {
  type        = string
  description = "AWS region (passed to ALB controller Helm values for VPC discovery)."
}

variable "vpc" {
  type = object({
    vpc_id = string
  })
  description = "VPC related inputs: vpc_id is the ID of the VPC where the ALB controller operates."
}

variable "eks" {
  type = object({
    name              = string
    oidc_provider_arn = string
  })
  description = "EKS cluster outputs: name and oidc_provider_arn (e.g. module.eks.outputs)."
}

variable "enable_metrics_server" {
  type        = bool
  default     = true
  description = "Whether to deploy the Kubernetes metrics-server (needed for kubectl top / HPA). Disable in shared clusters where a cluster-wide metrics-server already exists (only one can own the metrics.k8s.io APIService)."
}

# --- Namespaces ---
# Both the Retool application namespace and the supporting-services namespace are
# computed here (this module is the single source of truth) and exported via
# outputs so downstream modules (retool-helm, *-user-ingress) consume the same
# names rather than recomputing them. Leave null for the default prefixed names;
# set explicitly to target pre-existing namespaces in a shared cluster.

variable "retool_namespace" {
  type        = string
  default     = null
  description = "Namespace for the Retool application and the K8s objects that live beside it (ExternalSecrets, the namespaced SecretStore, the RR credentials Secret). When null, defaults to \"<prefix>-retool\"."
}

variable "services_namespace" {
  type        = string
  default     = null
  description = "Namespace for Retool's supporting operators (External Secrets Operator, reloader, cert-manager, ALB controller, metrics-server). When null, defaults to \"<prefix>-retool-services\"."
}

variable "create_namespaces" {
  type        = bool
  default     = true
  description = "Whether this module creates the retool and services namespaces. Set false in shared clusters where the namespaces (or the \"default\" namespace, if you override the names) are provisioned out of band."
}

# --- Per-release enable toggles ---
# All default true to preserve the from-scratch all-inclusive behavior. Flip the
# cluster-singleton operators off when deploying into a shared cluster that
# already runs them.

variable "enable_external_secrets" {
  type        = bool
  default     = true
  description = "Whether to install the External Secrets Operator (and its IAM/pod-identity wiring). Disable in shared clusters that already run ESO; the SecretStore and ExternalSecret resources are still created so the platform's ESO reconciles them."
}

variable "enable_reloader" {
  type        = bool
  default     = true
  description = "Whether to install Stakater reloader. When enabled it is scoped to only watch the retool namespace."
}

variable "enable_cert_manager" {
  type        = bool
  default     = true
  description = "Whether to install cert-manager (used by the ALB controller for its admission webhook certificate). Disable in shared clusters that already run cert-manager."
}

variable "enable_alb_controller" {
  type        = bool
  default     = true
  description = "Whether to install the AWS Load Balancer Controller. Disable in shared clusters that already run it."
}

variable "install_crds" {
  type        = bool
  default     = true
  description = "Whether the bundled operators install their CRDs (External Secrets, cert-manager). Set false in shared clusters where these cluster-scoped CRDs are already managed out of band."
}

variable "make_default_ingress_class" {
  type        = bool
  default     = false
  description = "Whether the ALB controller's IngressClass is marked the cluster-default IngressClass. Defaults false so this deployment never hijacks ingress for unrelated workloads in a shared cluster; Retool itself routes via a TargetGroupBinding and does not need a default class."
}

variable "default_tags" {
  type        = map(string)
  description = "Default tags applied to all taggable resources. Includes service identification by default."
  default = {
    "service" = "retool"
  }
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Extra tags merged on top of default_tags."
}

variable "encryption_key_secret_name" {
  type        = string
  default     = null
  description = "Name or ARN of an existing Secrets Manager secret to use as the Retool encryption key. If null, a random key is generated at retool/{prefix}/encryption-key. Provide a value to support data migration from an existing deployment."
}

# --- Existing-secret JSON properties ---
# Secrets this module generates hold a bare string, so no property is needed to
# read them. Secrets created by other tooling are often JSON objects, and the
# key holding the value varies (e.g. a CloudFormation GenerateSecretString
# secret nests it under "password"). Set the matching *_property variable to
# extract a single field instead of syncing the whole JSON blob.

variable "encryption_key_secret_property" {
  type        = string
  default     = null
  description = "JSON property to extract from encryption_key_secret_name. Leave null when the secret holds a bare string."
}

variable "jwt_secret_secret_path" {
  type        = string
  default     = null
  description = "Name or ARN of an existing Secrets Manager secret to use as the Retool JWT secret. If null, a random secret is generated at retool/{prefix}/jwt-secret. Provide a value to keep existing user sessions valid when migrating an existing deployment."
}

variable "jwt_secret_secret_property" {
  type        = string
  default     = null
  description = "JSON property to extract from jwt_secret_secret_path. Leave null when the secret holds a bare string."
}

variable "license_key_secret_property" {
  type        = string
  default     = null
  description = "JSON property to extract from license_key_secret_path. Leave null when the secret holds a bare string."
}

variable "db_password_secret_property" {
  type        = string
  default     = "password"
  description = "JSON property holding the database password within the secret at db.master_user_secret_arn. Defaults to \"password\", which matches both RDS-managed master user secrets and the Retool CloudFormation templates."
}

variable "extra_secret_read_arns" {
  type        = list(string)
  default     = []
  description = "Additional Secrets Manager secret ARNs (or ARN patterns) that External Secrets Operator is granted read access to. Use this when you author ExternalSecret manifests outside this module — e.g. credentials for a second database — that read secrets outside the retool/{prefix}/* namespace."
}

variable "license_key" {
  type        = string
  default     = null
  sensitive   = true
  description = "Retool license key. When set, stored in Secrets Manager and synced to a K8s Secret via ESO. Leave null for free-tier mode. Mutually exclusive with license_key_secret_path."
}

variable "license_key_secret_path" {
  type        = string
  default     = null
  description = "Name or ARN of an existing Secrets Manager secret holding the Retool license key. When set, ESO is granted read access and syncs it to the license-key K8s Secret, which retool-helm wires to config.licenseKeySecretName/licenseKeySecretKey. Mutually exclusive with license_key (which creates a managed secret instead)."
}

# --- Write-only secret version control ---
# These secret versions use write-only (secret_string_wo) values so the contents
# are never stored in Terraform state and out-of-band edits are not reverted as
# drift. Bump the corresponding *_wo_version to force Terraform to (re)write the
# managed value.

variable "encryption_key_wo_version" {
  type        = number
  default     = 1
  description = "Version counter for the generated encryption-key secret value. Increment to force Terraform to rewrite it."
}

variable "jwt_secret_wo_version" {
  type        = number
  default     = 1
  description = "Version counter for the generated jwt-secret secret value. Increment to force Terraform to rewrite it."
}

variable "extra_env_vars_wo_version" {
  type        = number
  default     = 1
  description = "Version counter for the extra-env-vars secret seed value. Increment to force Terraform to overwrite out-of-band edits back to the empty object."
}

variable "license_key_wo_version" {
  type        = number
  default     = 1
  description = "Version counter for the license-key secret value (only used when license_key is set). Increment to force Terraform to rewrite it."
}

variable "enable_agent_sandbox" {
  type        = bool
  default     = false
  description = "When true, generates agent sandbox secrets (JWT keypair, encryption key, API secret, Postgres URL) synced to K8s via ESO."
}

variable "db" {
  type = object({
    address                = string
    port                   = number
    name                   = string
    username               = string
    master_user_secret_arn = string
  })
  description = "Database outputs (e.g. module.db-main.outputs). Includes connection info and the Secrets Manager ARN for the master user credentials."
}

variable "enable_rr_s3" {
  type        = bool
  default     = false
  description = "Whether to create an S3 bucket and IAM service account for Retool Remote Repository storage."
}
