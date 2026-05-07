locals {
  cluster_name    = substr(var.prefix, 0, 38)
  cluster_version = var.cluster_version

  default_access_entries = {}

  access_entries = merge(local.default_access_entries, var.additional_access_entries)
  all_tags       = merge(var.default_tags, var.tags)
}

resource "aws_kms_key" "eks" {
  description = "Key for ${local.cluster_name} EKS cluster"
  tags        = local.all_tags
}

module "eks" {
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
    provider_key_arn = aws_kms_key.eks.arn
    resources        = ["secrets"]
  }

  addons = {
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
    # These addons MUST be installed before the node group (before_compute)
    # so that nodes can become Ready. Without vpc-cni the kubelet reports
    # "cni plugin not initialized" and the node stays NotReady forever,
    # causing the node group to fail CREATE after 25 min.
    eks-pod-identity-agent = {
      before_compute = true
    }
    kube-proxy = {
      before_compute = true
    }
    vpc-cni = {
      most_recent    = true
      preserve       = true
      before_compute = true
    }
  }

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
      # won't schedule on nodes it manages
      taints = {
        karpenter = {
          key    = "karpenter.sh/controller"
          value  = "true"
          effect = "NO_SCHEDULE"
        }
      }
      tags = {
        "karpenter.sh/discovery" = local.karpenter.discovery_value
      }

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
