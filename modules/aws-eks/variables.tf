variable "prefix" {
  type        = string
  description = "Prefix for resource names"
}

variable "region" {
  type        = string
  default     = ""
  description = "region name"
}

variable "vpc" {
  type = object({
    vpc_id             = string
    private_subnet_ids = list(string)
  })
  description = <<EOD
VPC related inputs:
  vpc_id: ID of the VPC in which the EKS cluster will be created
  private_subnet_ids: List of private subnet IDs to be used by the EKS cluster
EOD
}

variable "cluster_version" {
  type        = string
  default     = "1.32"
  description = "The version of the EKS cluster (use a version with available EKS optimized AMI in your region, e.g. 1.32)."
}

variable "endpoint_public_access" {
  type        = bool
  default     = true
  description = "Whether the EKS API server endpoint is publicly accessible. Set false for private-only clusters."
}

variable "cluster_encryption_kms_key_arn" {
  type        = string
  default     = null
  description = "ARN of an existing KMS key to encrypt EKS secrets with. If null, this module creates a key for the cluster. Supply a value when your organization mandates a specific CMK — the key cannot be changed after the cluster is created."
}

variable "enable_cluster_creator_admin_permissions" {
  type        = bool
  default     = true
  description = "Whether to enable cluster creator admin permissions."
}

# ---------------------------------------------------------------------------
# Controller node group sizing
# ---------------------------------------------------------------------------

variable "controller_instance_types" {
  type        = list(string)
  default     = ["t3a.medium"]
  description = "Instance types for the Karpenter controller node group."
}

variable "controller_min_size" {
  type        = number
  default     = 2
  description = "Minimum number of nodes in the Karpenter controller node group."
}

variable "controller_max_size" {
  type        = number
  default     = 5
  description = "Maximum number of nodes in the Karpenter controller node group."
}

variable "controller_desired_size" {
  type        = number
  default     = 2
  description = "Desired number of nodes in the Karpenter controller node group."
}

# ---------------------------------------------------------------------------
# Karpenter workload node configuration
# ---------------------------------------------------------------------------

variable "enable_karpenter" {
  type        = bool
  default     = true
  description = <<-EOT
    Whether to install Karpenter (CRDs, controller, IAM, and the default
    NodePool/EC2NodeClass) in kube-system. Karpenter is a cluster-wide singleton;
    disable it when bringing your own node autoscaling. When disabled, the
    controller node group is left untainted so it can run general workloads
    instead of being reserved for the (absent) Karpenter controller.
  EOT
}

variable "default_allowed_instance_types" {
  type        = list(string)
  default     = null
  description = "The EC2 instance types Karpenter can use to support EKS cluster workloads. If null, instances will only be restricted by family."
}

variable "default_allowed_instance_families" {
  type        = list(string)
  default     = ["m8i", "m8a", "r8i", "r8a", "m7i", "m7a", "r7i", "r7a"]
  description = "The EC2 instance families Karpenter can use to support EKS cluster workloads. If null, instances will only be restricted by type."
}

variable "default_allowed_architectures" {
  type        = list(string)
  default     = ["amd64"]
  description = "CPU architectures Karpenter may provision for the default NodePool. Retool publishes amd64-only images, so widening this will schedule pods onto nodes they cannot run on."
}

variable "karpenter_default_nodeclass_ami_selector_terms" {
  type        = any
  default     = null
  description = "If specified, override the included `default` nodeclass AMI selector terms."
}

variable "karpenter_default_nodepool_spec" {
  type        = any
  default     = null
  description = "If specified, override the included `default` nodepool spec."
}

variable "default_minimum_instance_memory_mib" {
  type        = number
  default     = 8000
  description = "Requires Karpenter to provision instances with strictly more memory (in MiB) than this value for the default NodePool. Karpenter only supports `Gt` (no `Gte`), so to include `*.large` (8192 MiB) use 8000; to include `*.xlarge` / r*.large (16384 MiB) use 16000. Defaults to 8000 to exclude `*.medium` and smaller — bursty workloads (e.g. agent-executor sandboxes) can consume far more than their declared pod memory requests, and tiny nodes risk system OOM that wedges kubelet. Set to `null` to disable the constraint."
}

variable "karpenter_replica_count" {
  type        = number
  default     = 1
  description = "Number of Karpenter controller replicas."
}

variable "enable_smarter_devices_net_tun_node_overlay" {
  type        = bool
  default     = true
  description = <<-EOT
    Whether to install a Karpenter NodeOverlay that advertises smarter-devices/net_tun
    capacity to the scheduler. Required for clusters running the agent-executor service:
    its executor pods request the resource (provided by smarter-device-manager) and
    Karpenter would otherwise refuse to scale up nodes for them. See
    https://github.com/kubernetes-sigs/karpenter/issues/751.
  EOT
}

# ---------------------------------------------------------------------------
# EBS CSI driver
# ---------------------------------------------------------------------------

variable "enable_ebs_csi_driver" {
  type        = bool
  default     = true
  description = "Whether to install the EBS CSI driver addon for persistent volume support."
}

# ---------------------------------------------------------------------------
# Metrics server
# ---------------------------------------------------------------------------

variable "enable_metrics_server" {
  type        = bool
  default     = true
  description = "Whether to install the EKS-managed metrics-server addon (needed for kubectl top / HPA). It is a cluster-wide singleton — only one copy can own the metrics.k8s.io APIService — so disable it if the cluster already runs one."
}

variable "launch_template_version" {
  type        = string
  default     = null
  description = "The version of the launch template to use for the Karpenter controller node group. If null, the latest version will be used."
}

variable "update_launch_template_default_version" {
  type        = bool
  default     = true
  description = "Whether to update the launch template default version when a new version is created. This is required for Karpenter to use the latest launch template version."
}

# ---------------------------------------------------------------------------
# Access entries
# ---------------------------------------------------------------------------

variable "additional_access_entries" {
  type        = map(any)
  description = "Additional access entries to add to the EKS cluster."
  default     = {}
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
  description = "Extra tags merged on top of default_tags."
  default     = {}
}
