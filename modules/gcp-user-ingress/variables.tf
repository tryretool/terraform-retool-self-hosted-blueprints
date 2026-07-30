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

variable "external_dns_chart" {
  type = object({
    repository       = string
    version          = string
    image_repository = string
    image_tag        = string
  })
  default = {
    repository       = "https://kubernetes-sigs.github.io/external-dns/"
    version          = "1.21.1"
    image_repository = "registry.k8s.io/external-dns/external-dns"
    image_tag        = "v0.21.0"
  }
  description = "Where to fetch the ExternalDNS chart and image. Defaults to upstream. Override to serve both from a private registry, which GCP Marketplace requires and restricted-egress installs need. Use an oci:// URL for repository when the chart lives in an OCI registry. Note the chart and app versions differ (chart 1.21.1 ships app v0.21.0)."
}
