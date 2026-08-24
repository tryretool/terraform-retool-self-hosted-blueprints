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
    oidc_issuer_url                      = string
    cert_manager_service_account_subject = optional(string)
  })
  description = "AKS cluster outputs (e.g. module.aks.outputs). oidc_issuer_url federates this deployment's managed identities; cert_manager_service_account_subject is the shared cert-manager controller's service account, which this deployment's DNS identity trusts so the controller can solve DNS-01 challenges against its zone."
}

variable "retool_service_port" {
  type        = number
  description = "Port on the Kubernetes Service that serves Retool traffic"
  default     = 3000
}

variable "retool_services" {
  type = object({
    retool_namespace = optional(string)
  })
  default     = null
  description = "Retool-services outputs (e.g. module.retool-services.outputs). The TLS Certificate, the Issuer and AGIC all live in retool_namespace, beside the Retool Ingress. When null, falls back to \"<prefix>-retool\"."
}

variable "enable_agic" {
  type        = bool
  default     = true
  description = "Whether to create the Application Gateway and install the AGIC controller for this deployment. Disable in shared clusters that already run an ingress controller, and set ingress_class_name to that controller's class so Retool's Ingress is reconciled by it."
}

variable "ingress_class_name" {
  type        = string
  default     = null
  description = "IngressClass this deployment's AGIC owns. When null, defaults to \"<prefix>-agic\", which is what lets several AGIC instances coexist in one cluster. Set it to point Retool's Ingress at an ingress controller you already run."
}

variable "cluster_issuer_name" {
  type        = string
  default     = null
  description = "Name of an existing cert-manager ClusterIssuer to issue Retool's certificate. When null, this module creates a namespaced Issuer named \"<prefix>-letsencrypt\" that solves Let's Encrypt DNS-01 challenges against the DNS zone it manages, using the cluster's shared cert-manager."
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
