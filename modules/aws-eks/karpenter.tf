// install karpenter CRDS
// install karpenter
// create default ec2 nodeclass and default nodepool
locals {
  karpenter = {
    cluster_name          = local.cluster_name
    namespace             = "kube-system"
    version               = "1.12.0"
    discovery_key         = "karpenter.sh/discovery"
    discovery_value       = local.cluster_name
    instance_profile_name = "KarpenterNodeInstanceProfile-${local.cluster_name}"
  }

  # Karpenter provisions EC2 instances via the AWS API at runtime, so the
  # provider's default_tags never reach them — we have to fold those into the
  # EC2NodeClass spec.tags explicitly. Module-level tags take precedence over
  # provider-level tags on collision.
  karpenter_node_tags = merge(data.aws_default_tags.current.tags, local.all_tags)
}

data "aws_default_tags" "current" {}

# NOTE: we use an instance_profile because the role changes between provisions
#       but the role is immutable on the ec2nodeclass
resource "aws_iam_instance_profile" "karpenter" {
  count = var.enable_karpenter ? 1 : 0

  name = local.karpenter.instance_profile_name
  role = module.eks.eks_managed_node_groups["karpenter"].iam_role_name
  tags = local.all_tags
}

module "karpenter" {
  count = var.enable_karpenter ? 1 : 0

  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "21.19.0"

  cluster_name        = local.karpenter.cluster_name
  namespace           = local.karpenter.namespace
  create_access_entry = false

  create_node_iam_role = false
  node_iam_role_arn    = module.eks.eks_managed_node_groups["karpenter"].iam_role_arn

  create_instance_profile = false
  enable_inline_policy    = true

  # Deterministic, prefix-based names for the controller IAM role and policy
  # instead of the chart default "KarpenterController-<random suffix>".
  iam_role_name              = "${local.cluster_name}-karpenter-controller"
  iam_role_use_name_prefix   = false
  iam_policy_name            = "${local.cluster_name}-karpenter-controller"
  iam_policy_use_name_prefix = false

  iam_role_tags = merge(local.all_tags, {
    karpenter = true
  })

  queue_name = "karpenter-${local.cluster_name}"

  depends_on = [
    module.eks,
  ]
}

resource "helm_release" "karpenter_crd" {
  count = var.enable_karpenter ? 1 : 0

  namespace        = local.karpenter.namespace
  create_namespace = false

  chart      = "karpenter-crd"
  name       = "karpenter-crd"
  repository = "oci://public.ecr.aws/karpenter"
  version    = local.karpenter.version

  wait = true

  values = [
    yamlencode({
      karpenter_namespace = local.karpenter.namespace
      webhook = {
        enabled     = true
        serviceName = "karpenter"
        port        = 8443
      }
    }),
  ]

  depends_on = [
    module.karpenter
  ]
}

resource "helm_release" "karpenter" {
  count = var.enable_karpenter ? 1 : 0

  namespace        = local.karpenter.namespace
  create_namespace = false

  chart      = "karpenter"
  name       = "karpenter"
  repository = "oci://public.ecr.aws/karpenter"
  version    = local.karpenter.version

  # https://github.com/aws/karpenter-provider-aws/blob/v1.2.2/charts/karpenter/values.yaml
  values = [
    yamlencode({
      replicas : var.karpenter_replica_count
      logLevel : "debug"
      settings : {
        clusterEndpoint : module.eks.cluster_endpoint
        clusterName : local.karpenter.cluster_name
        interruptionQueue : module.karpenter[0].queue_name
        batchMaxDuration : "15s" # a little longer than the default
        featureGates : {
          # NodeOverlay is alpha + off-by-default through at least 1.12. Required
          # so karpenter's scheduler simulator recognizes capacity declared by
          # NodeOverlay resources (e.g. smarter-devices/net_tun for agent-executor).
          nodeOverlay : true
        }
      }
      dnsPolicy : "ClusterFirst"
      controller : {
        resources : {
          requests : {
            cpu : 1
            memory : "1Gi"
          }
          limits : {
            cpu : 1
            memory : "1Gi"
          }
        }
      }
      serviceAccount : {
        annotations : {
          "eks.amazonaws.com/role-arn" : module.karpenter[0].iam_role_arn
        }
      }
      tolerations : [
        {
          key : "karpenter.sh/controller"
          value : "true"
          effect : "NoSchedule"
        },
        {
          key : "CriticalAddonsOnly"
          value : "true"
          effect : "NoSchedule"
        },
      ]
    }),
  ]

  lifecycle {
    ignore_changes = [
      repository_password
    ]
  }

  depends_on = [
    helm_release.karpenter_crd
  ]
}

#
# EC2NodeClass: default
# https://karpenter.sh/v1.0/concepts/nodeclasses/
#
locals {
  # https://karpenter.sh/v1.0/concepts/nodeclasses/#specamiselectorterms
  default_nodeclass_default_ami_selector_terms = [
    {
      alias = "al2023@latest"
    }
  ]
  # terraform's dumb type system gets confused if we use a ternary (x ? x : y)
  # to choose between these, so we have do trick it with a conditional list
  # index. bad terraform.
  default_nodeclass_ami_selector_terms = [
    var.karpenter_default_nodeclass_ami_selector_terms,
    local.default_nodeclass_default_ami_selector_terms,
  ][var.karpenter_default_nodeclass_ami_selector_terms != null ? 0 : 1]
}

resource "kubectl_manifest" "karpenter_ec2nodeclass_default" {
  count = var.enable_karpenter ? 1 : 0

  # reference: https://karpenter.sh/docs/concepts/nodeclasses/
  yaml_body = yamlencode({
    apiVersion = "karpenter.k8s.aws/v1"
    kind       = "EC2NodeClass"
    metadata = {
      name = "default"
    }
    spec = {
      instanceProfile  = "KarpenterNodeInstanceProfile-${local.karpenter.cluster_name}"
      amiSelectorTerms = local.default_nodeclass_ami_selector_terms
      metadataOptions = {
        httpEndpoint            = "enabled"
        httpProtocolIPv6        = "disabled"
        httpPutResponseHopLimit = 1
        httpTokens              = "required"
      }
      subnetSelectorTerms = [
        {
          tags = {
            "karpenter.sh/discovery" = local.karpenter.discovery_value
          }
        }
      ]
      securityGroupSelectorTerms = [
        {
          tags = {
            "karpenter.sh/discovery" = local.karpenter.discovery_value
          }
        }
      ]
      tags = local.karpenter_node_tags
    }
  })

  depends_on = [
    helm_release.karpenter
  ]
}

#
# nodepool: default
#
locals {
  # reference: https://karpenter.sh/docs/concepts/nodepools/
  default_nodepool_default_spec = {
    limits = {
      cpu    = 100
      memory = "200Gi"
    }
    template = {
      spec = {
        expireAfter = "732h"
        nodeClassRef = {
          group = "karpenter.k8s.aws"
          kind  = "EC2NodeClass"
          name  = "default"
        }
        requirements = concat([
          {
            key      = "karpenter.sh/capacity-type"
            operator = "In"
            values = [
              "on-demand",
            ]
          },
          merge({
            "key" = "node.kubernetes.io/instance-type"
            }, var.default_allowed_instance_types != null ? {
            "operator" = "In"
            "values"   = var.default_allowed_instance_types
            } : {
            "operator" = "Exists"
            "values"   = []
          }),
          merge({
            "key" = "karpenter.k8s.aws/instance-family"
            }, var.default_allowed_instance_families != null ? {
            "operator" = "In"
            "values"   = var.default_allowed_instance_families
            } : {
            "operator" = "Exists"
            "values"   = []
          }),
          # Retool publishes amd64-only images (the backend and the Temporal
          # image the workflows subchart runs). Without this, Karpenter is free
          # to pick arm64 and those pods crash with "exec format error".
          {
            key      = "kubernetes.io/arch"
            operator = "In"
            values   = var.default_allowed_architectures
          },
          {
            key      = "topology.kubernetes.io/zone"
            operator = "In"
            values = [ // this requires refinement
              "${var.region}a",
              "${var.region}b",
              "${var.region}c",
            ]
          },
          ], var.default_minimum_instance_memory_mib != null ? [
          {
            key      = "karpenter.k8s.aws/instance-memory"
            operator = "Gt"
            values   = [tostring(var.default_minimum_instance_memory_mib)]
          },
        ] : [])
      }
    }
    # https://karpenter.sh/v1.0/concepts/disruption/
    disruption = {
      consolidationPolicy = "WhenEmptyOrUnderutilized"
      consolidateAfter    = "5m"
      budgets = [
        // only allow one node to be disrupted at once
        {
          nodes = "1",
        },
      ]
    }
  }
  # terraform's dumb type system gets confused if we use a ternary (x ? x : y)
  # to choose between these, so we have do trick it with a conditional list
  # index. bad terraform.
  default_nodepool_spec = [
    var.karpenter_default_nodepool_spec,
    local.default_nodepool_default_spec,
  ][var.karpenter_default_nodepool_spec != null ? 0 : 1]
}

resource "kubectl_manifest" "karpenter_nodepool_default" {
  count = var.enable_karpenter ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "karpenter.sh/v1" # we are on v1 now
    kind       = "NodePool"
    metadata = {
      name = "default"
    }
    spec = local.default_nodepool_spec
  })

  depends_on = [
    kubectl_manifest.karpenter_ec2nodeclass_default,
    helm_release.karpenter,
  ]
}

#
# NodeOverlay: smarter-devices/net_tun (opt-in)
# https://karpenter.sh/docs/concepts/nodeoverlays/
#
# Tells Karpenter's scheduler simulator that any node provisioned from the
# default NodePool has 500 units of smarter-devices/net_tun. The actual
# resource is registered at runtime by the smarter-device-manager DaemonSet
# (deployed by the agent-executor helm chart) — Karpenter just needs to know
# the capacity exists ahead of time so it will scale up for executor pods.
#
resource "kubectl_manifest" "karpenter_nodeoverlay_smarter_devices_net_tun" {
  count = var.enable_karpenter && var.enable_smarter_devices_net_tun_node_overlay ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "karpenter.sh/v1alpha1"
    kind       = "NodeOverlay"
    metadata = {
      name = "smarter-devices-net-tun"
    }
    spec = {
      requirements = [
        {
          key      = "karpenter.sh/nodepool"
          operator = "In"
          values   = ["default"]
        },
      ]
      capacity = {
        "smarter-devices/net_tun" = "500"
      }
    }
  })

  depends_on = [
    kubectl_manifest.karpenter_nodepool_default,
    helm_release.karpenter,
    helm_release.karpenter_crd,
  ]
}
