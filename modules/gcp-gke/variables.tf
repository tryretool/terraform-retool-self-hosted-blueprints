variable "prefix" {
  type        = string
  description = "Prefix for all resource names"
}

variable "project_id" {
  type        = string
  description = "GCP project ID"
}

variable "region" {
  type        = string
  description = "GCP region for the cluster"
}

variable "vpc" {
  type = object({
    network_name        = string
    subnet_name         = string
    pods_range_name     = string
    services_range_name = string
  })
  default     = null
  description = "VPC outputs (e.g. module.vpc.outputs). Required when creating a cluster; when adopting one via existing_cluster the network is already fixed and this may be left null."
}

# Setting location to a region (default) creates a regional cluster with masters
# replicated across 3 zones — equivalent to EKS which always runs multi-AZ masters.
# Setting to a zone (e.g. "us-central1-a") creates a cheaper zonal cluster.
variable "location" {
  type        = string
  description = "Cluster location: a region for multi-zone masters, or a zone for a zonal cluster"
  default     = ""
}

# If set, maps to min_master_version and disables the release_channel (the two are
# mutually exclusive in the Google provider). Leave empty to use release_channel instead.
variable "cluster_version" {
  type        = string
  description = "Specific GKE cluster version (e.g. \"1.32\"). If set, disables release_channel."
  default     = ""
}

# Ignored when cluster_version is set.
variable "release_channel" {
  type        = string
  description = "GKE release channel: RAPID, REGULAR, or STABLE"
  default     = "REGULAR"
}

variable "node_machine_type" {
  type        = string
  description = "Machine type for application nodes"
  default     = "n2-standard-4"
}

variable "node_disk_size_gb" {
  type        = number
  description = "Boot disk size in GB for each node"
  default     = 100
}

variable "node_min_count" {
  type        = number
  description = "Minimum number of nodes per zone in the node pool"
  default     = 1
}

variable "node_max_count" {
  type        = number
  description = "Maximum number of nodes per zone in the node pool"
  default     = 10
}

# When set, only connections from the listed CIDR blocks can reach the master endpoint.
# If empty, the master endpoint is publicly accessible from any IP.
variable "master_authorized_networks" {
  type = list(object({
    cidr_block   = string
    display_name = string
  }))
  description = "List of CIDR blocks allowed to reach the GKE master endpoint"
  default     = []
}

variable "deletion_protection" {
  type        = bool
  description = "Prevent Terraform from destroying the cluster"
  default     = false
}

variable "default_tags" {
  type        = map(string)
  default     = { "service" = "retool" }
  description = "Default labels applied to all resources. Merged with var.tags (tags take precedence)."
}

variable "tags" {
  type        = map(string)
  description = "Labels to apply to GCP resources"
  default     = {}
}

# ---------------------------------------------------------------------------
# Existing cluster
# ---------------------------------------------------------------------------

variable "existing_cluster" {
  type = object({
    name       = string
    location   = string
    project_id = optional(string)
  })
  default     = null
  description = <<-EOT
    Adopt a pre-existing GKE cluster instead of creating one. When set, no
    cluster, node pool or node service account is created and the cluster's
    attributes are read from the live cluster; only the cluster-wide operators
    below are installed. Instantiate this module once per cluster.

      name: the existing cluster's name
      location: its region or zone. Unlike EKS/AKS this cannot be discovered,
        so it must be supplied.
      project_id: the project the cluster lives in, when it differs from
        var.project_id.

    The adopted cluster must have Workload Identity enabled — Retool's operators
    authenticate to Google APIs through it.
  EOT
}

variable "enable_gateway_api_check" {
  type        = bool
  default     = true
  description = "Whether adopting a cluster requires the Gateway API to be enabled on it. gcp-user-ingress needs the gke-l7-global-external-managed GatewayClass; set false if you route ingress another way."
}

# ---------------------------------------------------------------------------
# Cluster-wide operators
#
# These are cluster singletons: each owns CRDs and/or ClusterRoles whose names
# are fixed by the chart, so exactly one copy can exist per cluster and none can
# be installed once per Retool deployment. Each has an enable toggle so a cluster
# that already runs one can be adopted without a second copy fighting over it.
# ---------------------------------------------------------------------------

variable "enable_external_secrets" {
  type        = bool
  default     = true
  description = "Whether to install the External Secrets Operator in the external-secrets namespace. Disable if the cluster already runs it; each Retool deployment's SecretStore names its own service account either way."
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
  description = "Whether the bundled operators install their CRDs (External Secrets). These are cluster-scoped; set false only when they are already present and managed out of band."
}

variable "external_secrets_chart" {
  type = object({
    repository       = string
    version          = string
    image_repository = string
    image_tag        = string
  })
  default = {
    repository       = "https://charts.external-secrets.io"
    version          = "2.8.0"
    image_repository = "ghcr.io/external-secrets/external-secrets"
    image_tag        = "v2.8.0"
  }
  description = "Chart and image coordinates for the External Secrets Operator. Pinned explicitly because GCP Marketplace requires a fixed image set."
}

variable "reloader_chart" {
  type = object({
    repository       = string
    version          = string
    image_repository = string
    image_tag        = string
  })
  default = {
    repository       = "https://stakater.github.io/stakater-charts"
    version          = "2.2.14"
    image_repository = "ghcr.io/stakater/reloader"
    image_tag        = "v1.4.19"
  }
  description = "Chart and image coordinates for Stakater reloader. Pinned explicitly because GCP Marketplace requires a fixed image set."
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
