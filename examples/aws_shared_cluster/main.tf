###############################################################################
# Deploy Retool into a PRE-EXISTING (shared) EKS cluster.
#
# Unlike the aws_all_inclusive example, this does NOT create a VPC or an EKS
# cluster. It looks up an existing cluster + VPC by name and deploys only the
# Retool-specific pieces into dedicated, prefixed namespaces:
#   - <prefix>-retool           the Retool app + its Secrets
#   - <prefix>-retool-services  Retool's supporting operators (only the ones
#                               this deployment owns)
#
# Cluster-wide singletons (ESO, cert-manager, the ALB controller, metrics-server)
# are assumed to already exist in the shared cluster and are turned OFF here. The
# SecretStore + ExternalSecrets are still created (the platform's ESO reconciles
# them), and you must grant the platform ESO read access to Retool's secrets —
# attach module.retool-services.outputs.eso_irsa_role_arn to its service account
# (or replicate that policy onto whatever identity its controller uses).
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

# Resolve the cluster's IAM OIDC provider ARN (for IRSA / pod identity wiring).
data "aws_iam_openid_connect_provider" "this" {
  url = data.aws_eks_cluster.this.identity[0].oidc[0].issuer
}

# Shapes matching what the downstream modules expect, assembled from the data
# sources + the identifiers above.
locals {
  vpc = {
    vpc_id             = local.vpc_id
    private_subnet_ids = local.private_subnet_ids
    public_subnet_ids  = local.public_subnet_ids
  }
  eks = {
    name                   = data.aws_eks_cluster.this.name
    oidc_provider_arn      = data.aws_iam_openid_connect_provider.this.arn
    node_security_group_id = local.node_security_group_id
  }
}

module "db-main" {
  source  = "tryretool/self-hosted-blueprints/retool//modules/aws-database"
  version = "~> 0.3"

  prefix     = local.prefix
  db_purpose = "main"

  instance_class        = "db.t3.medium"
  allocated_storage     = 20
  max_allocated_storage = 200
  multi_az              = true

  vpc = local.vpc
  eks = { node_security_group_id = local.eks.node_security_group_id }
}

module "retool-services" {
  source  = "tryretool/self-hosted-blueprints/retool//modules/aws-retool-services"
  version = "~> 0.3"

  prefix = local.prefix
  region = local.region
  vpc    = { vpc_id = local.vpc.vpc_id }
  eks    = { name = local.eks.name, oidc_provider_arn = local.eks.oidc_provider_arn }
  db     = module.db-main.outputs

  # Namespaces default to <prefix>-retool / <prefix>-retool-services. Override
  # here to target namespaces the platform team pre-created, and set
  # create_namespaces = false so this module doesn't try to own them.
  # retool_namespace   = "team-retool"
  # services_namespace = "team-retool"
  # create_namespaces  = false

  # The shared cluster already runs these; don't install a second copy.
  enable_external_secrets = false
  enable_cert_manager     = false
  enable_alb_controller   = false
  enable_metrics_server   = false
  install_crds            = false
}

module "retool" {
  source  = "tryretool/self-hosted-blueprints/retool//modules/retool-helm"
  version = "~> 0.3"

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
  version = "~> 0.3"

  domain_name           = local.domain_name
  enable_https_listener = local.enable_user_ingress_https

  # TargetGroupBinding must land beside the Retool Service.
  retool_services = module.retool-services.outputs

  vpc = { vpc_id = local.vpc.vpc_id, public_subnet_ids = local.vpc.public_subnet_ids }
  eks = { node_security_group_id = local.eks.node_security_group_id }

  depends_on = [module.retool-services, module.retool]
}

output "modules" {
  sensitive = true # just to quiet the apply output
  value = {
    db-main         = module.db-main
    retool-services = module.retool-services
    user-ingress    = module.user-ingress
    retool          = module.retool
  }
}
