variable "prefix" {
  type        = string
  description = "Prefix for resource names"
}

variable "region" {
  type        = string
  default     = null
  description = "AWS region name. Defaults to the region the AWS provider is configured with."
}

variable "vpc" {
  type = object({
    vpc_id             = string
    private_subnet_ids = list(string)
  })
  default     = null
  description = <<EOD
VPC related inputs:
  vpc_id: ID of the VPC in which the EKS cluster will be created
  private_subnet_ids: List of private subnet IDs to be used by the EKS cluster

Required when creating a cluster. When adopting one via existing_cluster, the
VPC is read from the live cluster and this may be left null.
EOD

  validation {
    condition     = var.vpc != null || var.existing_cluster != null
    error_message = "vpc is required when creating a cluster. Set it, or set existing_cluster to adopt one."
  }
}

# ---------------------------------------------------------------------------
# Existing cluster
# ---------------------------------------------------------------------------

variable "existing_cluster" {
  type = object({
    name                   = string
    node_security_group_id = optional(string)
    oidc_provider_arn      = optional(string)
  })
  default     = null
  description = <<-EOT
    Adopt a pre-existing EKS cluster instead of creating one. When set, no
    cluster, KMS key or node group is created and the cluster's attributes are
    read from the live cluster; only the cluster-wide addons and operators below
    are installed. Use this to deploy Retool into a cluster you do not own, and
    instantiate this module once per cluster.

      name: the existing cluster's name
      node_security_group_id: the worker-node security group. Not discoverable
        from the cluster API, and required by the database and user-ingress
        modules so they can allow traffic to and from pods.
      oidc_provider_arn: the cluster's IAM OIDC provider. Looked up from the
        cluster's issuer URL when omitted; set it explicitly if the cluster has
        more than one, or provision one first — EKS does not create it for you,
        and IRSA-based addons need it.
  EOT
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

    Cannot be used together with existing_cluster: Karpenter is wired to the
    controller node group this module creates, which an adopted cluster does not
    have.
  EOT

  validation {
    condition     = !(var.enable_karpenter && var.existing_cluster != null)
    error_message = "enable_karpenter must be false when existing_cluster is set: Karpenter's IAM wiring depends on the controller node group, which is only created alongside a new cluster. Bring your own node autoscaling, or let this module create the cluster."
  }
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

# ---------------------------------------------------------------------------
# Core EKS addons
#
# Every addon and chart this module installs has an enable toggle, so a cluster
# that already runs one — or has it managed out of band — can be adopted without
# a second copy fighting over it. All default true.
# ---------------------------------------------------------------------------

variable "enable_coredns_addon" {
  type        = bool
  default     = true
  description = "Whether to install the CoreDNS addon. Only applies when creating a cluster; adopted clusters already have it."
}

variable "enable_kube_proxy_addon" {
  type        = bool
  default     = true
  description = "Whether to install the kube-proxy addon. Only applies when creating a cluster; adopted clusters already have it."
}

variable "enable_vpc_cni_addon" {
  type        = bool
  default     = true
  description = "Whether to install the VPC CNI addon. Only applies when creating a cluster; adopted clusters already have it. Nodes stay NotReady without a CNI, so do not disable this unless another CNI is installed out of band."
}

variable "enable_pod_identity_agent" {
  type        = bool
  default     = true
  description = "Whether to install the EKS Pod Identity agent addon. Required for the External Secrets Operator to receive credentials; disable only if the cluster already runs it."
}

# ---------------------------------------------------------------------------
# Cluster-wide operators
#
# These are cluster singletons: each owns CRDs, admission webhooks and/or
# ClusterRoles whose names are fixed by the chart, so exactly one copy can exist
# per cluster and it cannot be installed once per Retool deployment.
# ---------------------------------------------------------------------------

variable "enable_external_secrets" {
  type        = bool
  default     = true
  description = "Whether to install the External Secrets Operator in the external-secrets namespace, with a pod-identity role that per-deployment Retool ESO roles trust. Disable if the cluster already runs ESO; pass its controller's role ARN to aws-retool-services as eso_controller_role_arns instead."
}

variable "enable_cert_manager" {
  type        = bool
  default     = true
  description = "Whether to install cert-manager in the cert-manager namespace. Used by the ALB controller to issue its admission webhook certificate. Disable if the cluster already runs it."
}

variable "enable_alb_controller" {
  type        = bool
  default     = true
  description = "Whether to install the AWS Load Balancer Controller in the alb-controller namespace, with its IRSA role and policy. Disable if the cluster already runs it."
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
  description = "Whether the bundled operators install their CRDs (External Secrets, cert-manager). These are cluster-scoped; set false only when they are already present and managed out of band, in which case the operators must find them already installed."
}

variable "make_default_ingress_class" {
  type        = bool
  default     = false
  description = "Whether the ALB controller's IngressClass is marked the cluster-default IngressClass. Defaults false so this never displaces a default class the cluster already has; Retool routes via a TargetGroupBinding and does not need one."
}

variable "external_secrets_serve_v1beta1" {
  type        = bool
  default     = false
  description = "Whether the External Secrets CRDs keep serving the deprecated external-secrets.io/v1beta1 API. Chart 2.x stops serving it by default, which breaks Terraform's deletion of any SecretStore/ExternalSecret still recorded at v1beta1. Set true for the one apply that upgrades from a pre-v1 chart, then back to false."
}

variable "external_secrets_assumable_role_arns" {
  type        = list(string)
  default     = null
  description = "Role ARNs (wildcards allowed) the cluster External Secrets Operator may assume to read a deployment's secrets. When null, allows any role in this account whose name ends in \"-eso\", matching the <prefix>-eso roles aws-retool-services creates."
}

# ---------------------------------------------------------------------------
# Pod scheduling
# ---------------------------------------------------------------------------

variable "pod_node_selector" {
  type        = map(string)
  default     = {}
  description = "nodeSelector applied to every pod the cluster-wide Helm charts here create. Merged with each chart's own default (e.g. cert-manager's kubernetes.io/os: linux); empty keeps the chart defaults alone."
}

variable "pod_tolerations" {
  type        = any
  default     = []
  description = "Tolerations applied to every pod the cluster-wide Helm charts here create. Empty keeps each chart's own defaults."
}
