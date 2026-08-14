# Retool on EKS, migrated from an existing CloudFormation ECS/Fargate stack.
#
# Unlike the *_all_inclusive examples, this stack creates no VPC and no
# database — both are adopted from the CloudFormation deployment (see
# existing-network.tf and existing-database.tf). What it does create is the EKS
# cluster, the supporting cluster services, the Retool Helm release, and a new
# user-facing load balancer to cut over to.
#
# Configuration lives in variables.tf; copy vars.tf.example to terraform.tfvars.
#
# NOTE: module sources are local paths so this example plans against the modules
# in this repository. When copying it into your own working directory, switch
# them to the published registry modules:
#
#   source  = "tryretool/self-hosted-blueprints/retool//modules/aws-eks"
#   version = "~> 0.4"

module "eks" {
  source = "../../modules/aws-eks"

  prefix = var.prefix
  region = var.region
  vpc    = local.vpc
  tags   = var.tags

  cluster_version                = var.cluster_version
  cluster_encryption_kms_key_arn = var.cluster_encryption_kms_key_arn
  additional_access_entries      = var.eks_additional_access_entries

  # Karpenter selects subnets by tag, so the existing subnets must carry the
  # discovery tag before any node can be provisioned.
  depends_on = [aws_ec2_tag.karpenter_discovery]
}

module "retool-services" {
  source = "../../modules/aws-retool-services"

  prefix = var.prefix
  region = var.region
  vpc    = local.vpc
  eks    = module.eks.outputs
  db     = local.db
  tags   = var.tags

  # Carry the existing secrets over rather than generating new ones. The
  # encryption key in particular is load-bearing: every credential stored in the
  # Retool database is encrypted with it.
  encryption_key_secret_name     = var.encryption_key_secret.secret_id
  encryption_key_secret_property = var.encryption_key_secret.property

  jwt_secret_secret_path     = try(var.jwt_secret.secret_id, null)
  jwt_secret_secret_property = try(var.jwt_secret.property, null)

  license_key_secret_path     = try(var.license_key_secret.secret_id, null)
  license_key_secret_property = try(var.license_key_secret.property, null)

  db_password_secret_property = var.db.password_property

  # Lets External Secrets Operator read the Temporal database credentials, which
  # live outside the retool/{prefix}/* namespace. See temporal.tf.
  extra_secret_read_arns = compact([try(var.temporal.credentials_secret_id, null)])

  enable_agent_sandbox = var.enable_agent_sandbox
  enable_rr_s3         = var.enable_rr_s3

  depends_on = [module.eks]
}

module "retool" {
  source = "../../modules/retool-helm"

  retool_helm_name          = "retool"
  retool_helm_chart_version = var.retool_helm_chart_version

  db              = local.db
  retool_services = module.retool-services.outputs
  domain_name     = var.domain_name

  # The CloudFormation stack terminates TLS at the load balancer and runs with
  # COOKIE_INSECURE=false; https_enabled = true is the equivalent here. It also
  # drives the scheme in BASE_DOMAIN, so it has to track the ingress listener.
  https_enabled = var.enable_https

  # Workflows needs a Temporal cluster, which this stack only deploys when a
  # Temporal database is supplied.
  workflows_enabled = var.temporal != null

  retool_helm_extra_values = concat(
    local.app_values,
    local.temporal_values,
    local.cloudauth_values,
    var.retool_helm_extra_values,
  )

  # The Temporal pods mount temporal-db-credentials at startup, and the Helm
  # release waits for every Deployment to become ready — so the ExternalSecret
  # has to land first or the release times out on crashlooping Temporal pods.
  depends_on = [
    module.retool-services,
    kubectl_manifest.temporal_db_credentials,
  ]
}

module "user-ingress" {
  source = "../../modules/aws-user-ingress"

  domain_name           = var.domain_name
  enable_https_listener = var.enable_https

  vpc = local.vpc
  eks = module.eks.outputs

  # Bring the CloudFormation stack's certificate rather than minting a new one,
  # and only create a Route53 zone if neither a certificate nor an existing zone
  # was supplied — the usual migration case is that both are managed elsewhere.
  acm_certificate_arn = var.acm_certificate_arn
  create_hosted_zone  = var.acm_certificate_arn == null && var.hosted_zone_id == null
  hosted_zone_id      = var.hosted_zone_id

  # Edge authentication in front of Retool, mirroring the CloudFormation
  # stack's authenticate-oidc listener action. See alb-oidc.tf.
  alb_authenticate_oidc = local.alb_authenticate_oidc

  depends_on = [module.retool-services, module.retool]
}
