###############################################################################
# Two Retool instances — "dev" and "prod" — sharing one EKS cluster.
#
# Read guides/shared-clusters.md first. It explains which modules are shared and
# which are per-instance, and why; this example is just that guidance written
# out. The layout mirrors the guide:
#
#   shared.tf         the VPC and cluster, instantiated once
#   myretool-dev.tf   everything belonging to the dev instance
#   myretool-prod.tf  everything belonging to the prod instance
#
# Each Retool instance needs its own prefix, its own module names, and its own
# domain. Everything else follows from that.
###############################################################################

locals {
  # Shared by the resources below. Each instance derives its own prefix from
  # this, so names never collide.
  prefix_global = "acme-myretool"

  aws_profile = "retool"
  region      = "us-west-2"
  tags        = {}
}

module "vpc" {
  source  = "tryretool/self-hosted-blueprints/retool//modules/aws-vpc"
  version = "~> 0.4"

  prefix = local.prefix_global
}

# Installs the cluster-wide operators (External Secrets, cert-manager, reloader,
# the ALB controller) as singletons. Exactly one instantiation per cluster —
# adding a third Retool instance later means another myretool-*.tf, not another
# copy of this.
module "eks" {
  source  = "tryretool/self-hosted-blueprints/retool//modules/aws-eks"
  version = "~> 0.4"

  prefix = local.prefix_global
  region = local.region
  vpc    = module.vpc.outputs
}

output "shared" {
  sensitive = true # just to quiet the apply output
  value = {
    vpc = module.vpc
    eks = module.eks
  }
}
