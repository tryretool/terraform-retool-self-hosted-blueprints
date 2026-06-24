variable "prefix" {
  type        = string
  description = "Prefix for all resource names"
}

variable "resource_group_name" {
  type        = string
  description = "Name of the Azure resource group"
}

variable "location" {
  type        = string
  description = "Azure region"
}

variable "domain_name" {
  type        = string
  description = "Domain name for the Retool deployment (e.g. retool.example.com)"
}

variable "vnet" {
  type = object({
    appgw_subnet_id = string
  })
  description = <<-EOD
    VNet related inputs:
      appgw_subnet_id: ID of the Application Gateway dedicated subnet
  EOD
}

variable "aks" {
  type = object({
    oidc_issuer_url = string
  })
  description = "AKS cluster outputs for Workload Identity federation (e.g. module.aks.outputs)."
}

variable "retool_service_port" {
  type        = number
  description = "Port on the Kubernetes Service that serves Retool traffic"
  default     = 3000
}

variable "retool_services" {
  type = object({
    retool_namespace   = optional(string)
    services_namespace = optional(string)
  })
  default     = null
  description = "Retool-services outputs (e.g. module.retool-services.outputs). The TLS Certificate is created in retool_namespace (beside the Retool Ingress), and cert-manager/AGIC run in services_namespace. When null, falls back to the \"<prefix>-retool\" / \"<prefix>-retool-services\" defaults."
}

variable "enable_agic" {
  type        = bool
  default     = true
  description = "Whether to create the Application Gateway and install the AGIC controller. Disable in shared clusters that already run an ingress controller — set ingress_class_name to that controller's class so Retool's Ingress is reconciled by it."
}

variable "enable_cert_manager" {
  type        = bool
  default     = true
  description = "Whether to install cert-manager (and create its DNS-01 managed identity + ClusterIssuer). Only relevant when enable_https is true. Disable in shared clusters that already run cert-manager and pass cluster_issuer_name pointing at an existing ClusterIssuer."
}

variable "install_crds" {
  type        = bool
  default     = true
  description = "Whether the bundled cert-manager installs its CRDs. Set false in shared clusters where these cluster-scoped CRDs are already managed out of band."
}

variable "ingress_class_name" {
  type        = string
  default     = "azure-application-gateway"
  description = "ingressClassName Retool's Ingress is annotated with. Defaults to AGIC's class; override to target a different ingress controller in a shared cluster."
}

variable "cluster_issuer_name" {
  type        = string
  default     = null
  description = "Name of the cert-manager ClusterIssuer the TLS Certificate references. When null, this module creates a \"letsencrypt-prod\" ClusterIssuer (requires enable_cert_manager). Set to an existing issuer's name to consume the platform's cert-manager instead."
}

variable "enable_https" {
  type        = bool
  description = <<-EOT
    When true, deploy cert-manager and provision a Let's Encrypt TLS certificate
    via DNS-01 challenge using Azure DNS. The Application Gateway terminates TLS
    on port 443 with an HTTP-to-HTTPS redirect.
    When false, the Application Gateway serves Retool on HTTP port 80 only —
    suitable for initial apply before DNS delegation.
  EOT
  default     = false
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags applied to all resources created by this module"
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
