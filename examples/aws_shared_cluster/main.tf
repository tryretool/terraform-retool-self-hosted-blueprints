###############################################################################
# Deploy Retool into a PRE-EXISTING (shared) EKS cluster.
#
# Unlike the aws_all_inclusive example, this creates no VPC and no EKS cluster.
# It points aws-eks at an existing cluster via existing_cluster, which installs
# only the cluster-wide operators Retool needs, and puts the Retool deployment
# itself in a single prefixed namespace, <prefix>-retool.
#
# The operators (External Secrets, cert-manager, the ALB controller, reloader)
# are cluster singletons — their CRDs, admission webhooks and ClusterRoles have
# fixed cluster-scoped names, so exactly one copy can exist per cluster. Turn off
# the ones your platform team already runs. To add a SECOND Retool deployment to
# this cluster, do not instantiate aws-eks again: deploy only retool-services,
# retool-helm and user-ingress with a different prefix.
###############################################################################

locals {
  prefix      = "retool-prod"
  aws_profile = "retool"
  region      = "us-west-2"
  tags        = {}
  domain_name = "retool.mydomain.com" # Replace with your actual customer domain

  enable_user_ingress_https = false

  # --- Existing shared infrastructure you must point at ---
  cluster_name = "my-shared-eks"  # existing EKS cluster name
  vpc_id       = "vpc-0123456789" # the cluster's VPC
  # The EKS worker-node security group. The user ALB must be allowed to reach
  # pods through it, and RDS must allow ingress from it. Find it on your node
  # group / launch template (it is not exposed by the aws_eks_cluster data source).
  node_security_group_id = "sg-0123456789"
  # Private subnets for RDS; public subnets for the user-facing ALB.
  private_subnet_ids = ["subnet-aaa", "subnet-bbb"]
  public_subnet_ids  = ["subnet-ccc", "subnet-ddd"]
}

data "aws_eks_cluster" "this" {
  name = local.cluster_name
}

# Shapes matching what the downstream modules expect, assembled from the
# identifiers above.
locals {
  vpc = {
    vpc_id             = local.vpc_id
    private_subnet_ids = local.private_subnet_ids
    public_subnet_ids  = local.public_subnet_ids
  }
}

# Adopts the existing cluster rather than creating one: no VPC, no node groups,
# no Karpenter — only the cluster-wide operators. Instantiate this once per
# cluster, from one Terraform state.
module "eks" {
  source  = "tryretool/self-hosted-blueprints/retool//modules/aws-eks"
  version = "~> 0.4"

  prefix = local.prefix
  region = local.region

  existing_cluster = {
    name                   = local.cluster_name
    node_security_group_id = local.node_security_group_id
  }

  # Karpenter is wired to the controller node group this module creates when it
  # creates a cluster, so it cannot run against an adopted one.
  enable_karpenter = false

  # The cluster addons are managed by EKS and an existing cluster almost
  # certainly already has them.
  enable_ebs_csi_driver = false
  enable_metrics_server = false

  # Turn off any of these your platform team already runs cluster-wide.
  enable_external_secrets = true
  enable_cert_manager     = true
  enable_alb_controller   = true
  enable_reloader         = true

  # Set false if the CRDs are already installed and managed out of band.
  install_crds = true

  # Leave false so this never displaces a default IngressClass the cluster
  # already has; Retool routes via a TargetGroupBinding and does not need one.
  make_default_ingress_class = false
}

module "db-main" {
  source  = "tryretool/self-hosted-blueprints/retool//modules/aws-database"
  version = "~> 0.4"

  prefix     = local.prefix
  db_purpose = "main"

  instance_class        = "db.t3.medium"
  allocated_storage     = 20
  max_allocated_storage = 200
  multi_az              = true

  vpc = local.vpc
  eks = { node_security_group_id = local.node_security_group_id }
}

module "retool-services" {
  source  = "tryretool/self-hosted-blueprints/retool//modules/aws-retool-services"
  version = "~> 0.4"

  prefix = local.prefix
  region = local.region
  db     = module.db-main.outputs

  # Supplies the cluster ESO controller's role ARN. This deployment's
  # <prefix>-eso role trusts it, so the controller can assume that role to read
  # these secrets — and only these secrets.
  eks = module.eks.outputs

  # If your platform team runs the External Secrets Operator instead
  # (enable_external_secrets = false above), name its controller's role here:
  # eso_controller_role_arns = ["arn:aws:iam::123456789012:role/platform-eso"]

  # The namespace defaults to <prefix>-retool. Override to target a namespace
  # the platform team pre-created, and set create_namespace = false so this
  # module doesn't try to own it.
  # retool_namespace = "team-retool"
  # create_namespace = false

  # The SecretStore and ExternalSecrets must land after the operator's CRDs.
  depends_on = [module.eks]
}

module "retool" {
  source  = "tryretool/self-hosted-blueprints/retool//modules/retool-helm"
  version = "~> 0.4"

  retool_helm_name          = "retool"
  retool_helm_chart_version = "6.11.1"

  # namespace flows in automatically via retool_services.retool_namespace
  db              = module.db-main.outputs
  retool_services = module.retool-services.outputs
  domain_name     = local.domain_name
  https_enabled   = local.enable_user_ingress_https

  retool_helm_extra_values = [yamlencode({
    image = {
      tag = "3.334.0-stable"
    }
    podDisruptionBudget = {
      maxUnavailable = 1
    }
  })]

  depends_on = [module.retool-services]
}

module "user-ingress" {
  source  = "tryretool/self-hosted-blueprints/retool//modules/aws-user-ingress"
  version = "~> 0.4"

  domain_name           = local.domain_name
  enable_https_listener = local.enable_user_ingress_https

  # TargetGroupBinding must land beside the Retool Service.
  retool_services = module.retool-services.outputs

  vpc = { vpc_id = local.vpc.vpc_id, public_subnet_ids = local.vpc.public_subnet_ids }
  eks = { node_security_group_id = local.node_security_group_id }

  depends_on = [module.retool-services, module.retool]
}

output "modules" {
  sensitive = true # just to quiet the apply output
  value = {
    eks             = module.eks
    db-main         = module.db-main
    retool-services = module.retool-services
    user-ingress    = module.user-ingress
    retool          = module.retool
  }
}
