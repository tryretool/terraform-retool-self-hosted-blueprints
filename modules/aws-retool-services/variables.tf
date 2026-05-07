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
  description = "Whether to deploy the Kubernetes metrics-server (needed for kubectl top / HPA)."
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

variable "license_key" {
  type        = string
  default     = null
  sensitive   = true
  description = "Retool license key. When set, stored in Secrets Manager and synced to a K8s Secret via ESO. Leave null for free-tier mode."
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

variable "enable_rr_git_s3" {
  type        = bool
  default     = false
  description = "Whether to create an S3 bucket and IAM service account for Retool Remote Repository Git storage."
}
