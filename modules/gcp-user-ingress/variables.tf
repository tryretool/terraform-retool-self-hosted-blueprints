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

variable "retool_services" {
  type = object({
    retool_namespace = optional(string)
  })
  default     = null
  description = "Retool-services outputs (e.g. module.retool-services.outputs). The Gateway, HTTPRoute, HealthCheckPolicy and external-dns are all created in retool_namespace, beside the Retool Service. When null, falls back to \"<prefix>-retool\"."
}

variable "enable_external_dns" {
  type        = bool
  default     = true
  description = "Whether to install external-dns. Disable in shared clusters that already run it (the Cloud DNS zone and Gateway are still created; you must point your existing external-dns at the zone)."
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

# Pod scheduling — applied to every pod this module schedules via Helm. In a
# shared cluster with dedicated/labelled/tainted node pools, set these so the
# pods land on (and tolerate) the right nodes. See local.pod_scheduling in
# pod-scheduling.tf for how they are merged into each chart's values.
variable "pod_node_selector" {
  type        = map(string)
  default     = {}
  description = "nodeSelector applied to every pod this module schedules (all Helm charts/components). Empty = unset (chart defaults apply)."
}

variable "pod_tolerations" {
  # A list of Kubernetes toleration objects (key/operator/value/effect/tolerationSeconds),
  # passed verbatim into Helm values. Typed `any` to avoid rendering omitted fields as null.
  type        = any
  default     = []
  description = "Tolerations applied to every pod this module schedules. A list of Kubernetes toleration objects. Empty = unset."
}
