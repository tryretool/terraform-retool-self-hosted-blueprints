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

variable "base_domain" {
  type        = string
  description = "Base domain for the Retool deployment (e.g. \"retool.example.com\"). Used for the Cloud DNS zone, Certificate Manager certificate, and Gateway routing."
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Labels applied to GCP resources."
}
