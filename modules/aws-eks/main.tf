locals {
  byo_cluster     = var.existing_cluster != null
  cluster_name    = local.byo_cluster ? var.existing_cluster.name : substr(var.prefix, 0, 38)
  cluster_version = var.cluster_version

  # var.region has always been optional here; fall back to the provider's region
  # rather than interpolating an empty string into IAM policies, chart values and
  # Karpenter's availability-zone terms.
  region = coalesce(var.region, data.aws_region.current.region)

  default_access_entries = {}

  access_entries = merge(local.default_access_entries, var.additional_access_entries)
  all_tags       = merge(var.default_tags, var.tags)

  cluster_encryption_kms_key_arn = coalesce(
    var.cluster_encryption_kms_key_arn,
    one(aws_kms_key.eks[*].arn),
  )
}

resource "aws_kms_key" "eks" {
  count = !local.byo_cluster && var.cluster_encryption_kms_key_arn == null ? 1 : 0

  description = "Key for ${local.cluster_name} EKS cluster"
  tags        = local.all_tags
}

# This key became conditional in v0.4. Keeps existing deployments from planning a
# destroy/create when their state still records it at its pre-count address —
# which would be especially bad here, since the EKS secret encryption key cannot
# be changed after the cluster is created.
moved {
  from = aws_kms_key.eks
  to   = aws_kms_key.eks[0]
}

module "eks" {
  count = local.byo_cluster ? 0 : 1

  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"

  name                    = local.cluster_name
  kubernetes_version      = local.cluster_version
  endpoint_private_access = true
  endpoint_public_access  = var.endpoint_public_access

  vpc_id     = var.vpc.vpc_id
  subnet_ids = var.vpc.private_subnet_ids

  create_kms_key = false
  encryption_config = {
    provider_key_arn = local.cluster_encryption_kms_key_arn
    resources        = ["secrets"]
  }

  addons = merge(
    var.enable_coredns_addon ? {
      coredns = {
        # CoreDNS needs a running node to schedule on, so it must come after
        # the node group. We add tolerations so it can run on Karpenter
        # controller nodes during initial cluster creation.
        configuration_values = jsonencode({
          tolerations = [
            {
              key    = "karpenter.sh/controller"
              value  = "true"
              effect = "NoSchedule"
            },
            {
              key    = "CriticalAddonsOnly"
              value  = "true"
              effect = "NoSchedule"
            },
          ]
        })
      }
    } : {},
    # These addons MUST be installed before the node group (before_compute)
    # so that nodes can become Ready. Without vpc-cni the kubelet reports
    # "cni plugin not initialized" and the node stays NotReady forever,
    # causing the node group to fail CREATE after 25 min.
    var.enable_pod_identity_agent ? {
      "eks-pod-identity-agent" = {
        before_compute = true
      }
    } : {},
    var.enable_kube_proxy_addon ? {
      "kube-proxy" = {
        before_compute = true
      }
    } : {},
    var.enable_vpc_cni_addon ? {
      "vpc-cni" = {
        most_recent    = true
        preserve       = true
        before_compute = true
      }
    } : {},
  )

  authentication_mode                      = "API_AND_CONFIG_MAP"
  access_entries                           = local.access_entries
  enable_cluster_creator_admin_permissions = var.enable_cluster_creator_admin_permissions
  eks_managed_node_groups = {
    karpenter = {
      instance_types = var.controller_instance_types
      min_size       = var.controller_min_size
      max_size       = var.controller_max_size
      desired_size   = var.controller_desired_size

      # block_device_mappings is required because the upstream module uses a
      # custom launch template, which causes the top-level disk_size to be
      # ignored.  Without this the node boots with 0-capacity image filesystem
      # and kubelet reports InvalidDiskCapacity.
      block_device_mappings = {
        xvda = {
          device_name = "/dev/xvda"
          ebs = {
            volume_size           = 50
            volume_type           = "gp3"
            encrypted             = true
            delete_on_termination = true
          }
        }
      }

      # Used to ensure Karpenter runs on nodes that it does not manage
      labels = {
        "karpenter.sh/controller" = "true"
      }
      # Reserve this node group for the Karpenter controller (which won't run on
      # nodes Karpenter itself manages). When Karpenter is disabled there is no
      # controller to host, so leave the group untainted for general workloads.
      taints = var.enable_karpenter ? {
        karpenter = {
          key    = "karpenter.sh/controller"
          value  = "true"
          effect = "NO_SCHEDULE"
        }
      } : {}

      launch_template_version                = var.launch_template_version
      update_launch_template_default_version = var.update_launch_template_default_version

      tags = merge(local.all_tags, {
        "karpenter.sh/discovery" = local.karpenter.discovery_value
      })

      iam_role_additional_policies = {
        additional = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
      }
    }
  }

  node_security_group_tags = merge(local.all_tags, {
    "kubernetes.io/cluster/${local.cluster_name}" = null
    "karpenter.sh/discovery"                      = local.karpenter.discovery_value
  })

  tags = merge(local.all_tags, {
    "karpenter.sh/discovery" = local.karpenter.discovery_value
  })
}
