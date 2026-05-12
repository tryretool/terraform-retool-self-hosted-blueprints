variable "prefix" {
  type        = string
  description = "Prefix for resource names."
}

variable "project_id" {
  type        = string
  description = "GCP project ID."
}

variable "region" {
  type        = string
  description = "GCP region."
}

variable "domain_name" {
  type        = string
  description = "Domain name for the Retool deployment (e.g. \"retool.example.com\"). Used for the Cloud DNS zone, Certificate Manager certificate, and Gateway routing."
}

variable "default_tags" {
  type        = map(string)
  default     = { "service" = "retool" }
  description = "Default labels applied to all resources. Merged with var.tags (tags take precedence)."
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Labels applied to GCP resources."
}
