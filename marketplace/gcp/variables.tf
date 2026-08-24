variable "project_id" {
  type        = string
  description = "GCP project that will host the deployment. Marketplace supplies this."
}

variable "goog_cm_deployment_name" {
  type        = string
  default     = ""
  description = "Marketplace deployment name. Auto-populated by the Marketplace UI and used to avoid resource name collisions."
}

variable "region" {
  type        = string
  description = "GCP region for the VPC, GKE cluster, and Cloud SQL."
  default     = "us-central1"
}

variable "prefix" {
  type        = string
  description = "Short prefix for resource names (kept short for GCP 30-char SA IDs). Empty uses a truncated goog_cm_deployment_name."
  default     = ""
}

variable "domain_name" {
  type        = string
  description = "Hostname that will serve Retool (e.g. retool.example.com). Delegate its NS records to the Cloud DNS zone this module creates."
}

variable "license_key" {
  type        = string
  default     = ""
  sensitive   = true
  description = "Retool license key. Leave empty for free-tier mode."
}

# Marketplace rewrites these three on publish to the Google-owned chart copy.
variable "helm_chart_repo" {
  type        = string
  description = "OCI or HTTPS repo that hosts the Retool Helm chart."
  default     = "oci://us-docker.pkg.dev/retool-public/terraform-app-staging/retool-blueprints/charts"
}

variable "helm_chart_name" {
  type        = string
  description = "Retool Helm chart name under helm_chart_repo."
  default     = "retool"
}

variable "helm_chart_version" {
  type        = string
  description = "Chart tag. Producer Portal requires a semantic minor version (e.g. 4.0)."
  default     = "4.0"
}

variable "helm_release_name" {
  type        = string
  default     = ""
  description = "Helm release name. Empty uses \"retool\"."
}

variable "third_party_charts_repo" {
  type        = string
  description = "OCI repo for the External Secrets, Reloader, and ExternalDNS charts. Separate from helm_chart_repo so Marketplace's rewrite of the Retool chart does not retarget these."
  default     = "oci://us-docker.pkg.dev/retool-public/terraform-app-staging/retool-blueprints/charts"
}

# Image vars below are declared in schema.yaml. Marketplace overwrites them
# with the Google-owned Artifact Registry copies at publish time.

variable "image_repo" {
  type        = string
  default     = "us-docker.pkg.dev/retool-public/terraform-app-staging/retool-blueprints"
  description = "Retool backend image repository."
}

variable "image_tag" {
  type        = string
  default     = "4.0"
  description = "Retool backend / code-executor image tag."
}

variable "code_executor_image_repo" {
  type        = string
  default     = "us-docker.pkg.dev/retool-public/terraform-app-staging/retool-blueprints/code-executor-service"
  description = "Code-executor image repository."
}

variable "code_executor_image_tag" {
  type        = string
  default     = "4.0"
  description = "Code-executor image tag."
}

variable "js_executor_image_repo" {
  type        = string
  default     = "us-docker.pkg.dev/retool-public/terraform-app-staging/retool-blueprints/js-executor-service"
  description = "JS-executor image repository."
}

variable "js_executor_image_tag" {
  type        = string
  default     = "4.0"
  description = "JS-executor image tag."
}

variable "agent_sandbox_image_repo" {
  type        = string
  default     = "us-docker.pkg.dev/retool-public/terraform-app-staging/retool-blueprints/agent-sandbox-service"
  description = "Agent-sandbox image repository."
}

variable "agent_sandbox_image_tag" {
  type        = string
  default     = "4.0"
  description = "Agent-sandbox image tag."
}

variable "telemetry_image_repo" {
  type        = string
  default     = "us-docker.pkg.dev/retool-public/terraform-app-staging/retool-blueprints/telemetry"
  description = "Telemetry image repository."
}

variable "telemetry_image_tag" {
  type        = string
  default     = "4.0"
  description = "Telemetry image tag."
}

variable "external_secrets_image_repo" {
  type        = string
  default     = "us-docker.pkg.dev/retool-public/terraform-app-staging/retool-blueprints/external-secrets"
  description = "External Secrets Operator image repository."
}

variable "external_secrets_image_tag" {
  type        = string
  default     = "v2.8.0"
  description = "External Secrets Operator image tag."
}

variable "reloader_image_repo" {
  type        = string
  default     = "us-docker.pkg.dev/retool-public/terraform-app-staging/retool-blueprints/reloader"
  description = "Reloader image repository."
}

variable "reloader_image_tag" {
  type        = string
  default     = "v1.4.19"
  description = "Reloader image tag."
}

variable "external_dns_image_repo" {
  type        = string
  default     = "us-docker.pkg.dev/retool-public/terraform-app-staging/retool-blueprints/external-dns"
  description = "ExternalDNS image repository."
}

variable "external_dns_image_tag" {
  type        = string
  default     = "v0.21.0"
  description = "ExternalDNS image tag."
}

variable "busybox_image_repo" {
  type        = string
  default     = "us-docker.pkg.dev/retool-public/terraform-app-staging/retool-blueprints/busybox"
  description = "Busybox init image repository (agent-sandbox prepuller)."
}

variable "busybox_image_tag" {
  type        = string
  default     = "1.37.0"
  description = "Busybox init image tag."
}

variable "smarter_device_manager_image_repo" {
  type        = string
  default     = "us-docker.pkg.dev/retool-public/terraform-app-staging/retool-blueprints/smarter-device-manager"
  description = "smarter-device-manager image repository."
}

variable "smarter_device_manager_image_tag" {
  type        = string
  default     = "v1.20.12"
  description = "smarter-device-manager image tag."
}
