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

variable "vnet" {
  type = object({
    aks_subnet_id = string
  })
  default     = null
  description = <<-EOD
    VNet related inputs:
      aks_subnet_id: ID of the AKS node pool subnet
  EOD

  validation {
    condition     = var.vnet != null || var.existing_cluster != null
    error_message = "vnet is required when creating a cluster. Set it, or set existing_cluster to adopt one."
  }
}

variable "kubernetes_version" {
  type        = string
  description = "Kubernetes version for the AKS cluster"
  default     = "1.34"
}

variable "node_vm_size" {
  type        = string
  description = "VM size for the default node pool. See [Azure VM size documentation](https://learn.microsoft.com/en-us/azure/virtual-machines/sizes/general-purpose/d-family) or use `az vm list-skus` to find available sizes in your region. Recommended minimum is Standard_D4as_v4 or equivalent (4 cpu, 16Gi memory) for production Retool deployments."
  default     = "Standard_D4as_v6"
}

variable "node_os_disk_size_gb" {
  type        = number
  description = "OS disk size in GB for each node"
  default     = 100
}

variable "node_min_count" {
  type        = number
  description = "Minimum number of nodes in the default pool"
  default     = 2
}

variable "node_max_count" {
  type        = number
  description = "Maximum number of nodes in the default pool"
  default     = 8
}

variable "api_server_authorized_ip_ranges" {
  type        = list(string)
  description = "CIDR ranges allowed to reach the AKS API server. Empty list means unrestricted (public)."
  default     = []
}

variable "log_analytics_retention_days" {
  type        = number
  description = "Log Analytics workspace retention in days"
  default     = 30
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags applied to all resources created by this module"
}

# ---------------------------------------------------------------------------
# Existing cluster
# ---------------------------------------------------------------------------

variable "existing_cluster" {
  type = object({
    name                = string
    resource_group_name = optional(string)
  })
  default     = null
  description = <<-EOT
    Adopt a pre-existing AKS cluster instead of creating one. When set, no
    cluster and no log analytics workspace are created and the cluster's
    attributes are read from the live cluster; only the cluster-wide operators
    below are installed. Instantiate this module once per cluster.

      name: the existing cluster's name
      resource_group_name: the group it lives in, when it differs from
        var.resource_group_name.

    The adopted cluster must have oidc_issuer_enabled and workload_identity_enabled
    set — every identity Retool creates is federated against that issuer.
  EOT
}

# ---------------------------------------------------------------------------
# Cluster-wide operators
#
# These are cluster singletons: each owns CRDs, admission webhooks and/or
# ClusterRoles whose names are fixed by the chart, so exactly one copy can exist
# per cluster and none can be installed once per Retool deployment. Each has an
# enable toggle so a cluster that already runs one can be adopted without a
# second copy fighting over it.
# ---------------------------------------------------------------------------

variable "enable_external_secrets" {
  type        = bool
  default     = true
  description = "Whether to install the External Secrets Operator in the external-secrets namespace. Disable if the cluster already runs it; each Retool deployment's SecretStore names its own service account either way."
}

variable "enable_cert_manager" {
  type        = bool
  default     = true
  description = "Whether to install cert-manager in the cert-manager namespace. Azure has no ACM equivalent, so azure-user-ingress uses it to issue Let's Encrypt certificates via DNS-01 against Azure DNS. Disable if the cluster already runs it."
}

variable "enable_reloader" {
  type        = bool
  default     = true
  description = "Whether to install Stakater reloader in the reloader namespace, which restarts workloads when the ConfigMaps and Secrets they reference change. Disable if the cluster already runs it."
}

variable "reloader_auto_reload_all" {
  type        = bool
  default     = true
  description = "Whether reloader watches every workload in the cluster rather than only those carrying reloader.stakater.com/* annotations. Set false in a shared cluster where restarting other teams' workloads is unacceptable; Retool's own chart annotates its workloads, so it keeps working either way."
}

variable "install_crds" {
  type        = bool
  default     = true
  description = "Whether the bundled operators install their CRDs (External Secrets, cert-manager). These are cluster-scoped; set false only when they are already present and managed out of band."
}

variable "external_secrets_serve_v1beta1" {
  type        = bool
  default     = false
  description = "Whether the External Secrets CRDs keep serving the deprecated external-secrets.io/v1beta1 API. Chart 2.x stops serving it by default, which breaks Terraform's deletion of any SecretStore/ExternalSecret still recorded at v1beta1. Set true for the one apply that upgrades from a pre-v1 chart, then back to false."
}

# ---------------------------------------------------------------------------
# Pod scheduling
# ---------------------------------------------------------------------------

variable "pod_node_selector" {
  type        = map(string)
  default     = {}
  description = "nodeSelector applied to every pod the cluster-wide Helm charts here create. Merged with each chart's own defaults; empty keeps the chart defaults alone."
}

variable "pod_tolerations" {
  type        = any
  default     = []
  description = "Tolerations applied to every pod the cluster-wide Helm charts here create. Empty keeps each chart's own defaults."
}
