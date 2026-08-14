# Retool on EKS, adopting the databases from an existing CloudFormation
# ECS/Fargate stack.
#
# Where aws_migrate_from_cloudformation only *reads* the databases and leaves
# them under CloudFormation's control, this example **imports** them into
# Terraform state, so the CloudFormation stack can eventually be deleted without
# taking them along.
#
# The requirement throughout is that the running ECS deployment keeps working:
# both deployments share one database, and the cutover is a DNS switch at the
# end. Three module settings exist for exactly that — see the comments on
# module.db-main below.
#
# Run import_from_cloudformation.py before the first apply; see README.md.
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

# The imported Retool database. Nothing here creates anything: every value is
# what the database already is, so that `terraform apply` after the import is a
# no-op against it.
module "db-main" {
  source = "../../modules/aws-database"

  prefix     = var.prefix
  db_purpose = "main"
  identifier = var.retool_db.identifier
  tags       = var.tags

  vpc = local.vpc
  eks = module.eks.outputs

  # Leave the password where CloudFormation put it. If RDS took over managing it,
  # it would generate a new one and the running ECS tasks would lose access to
  # the database immediately.
  manage_master_user_password = false
  master_user_secret_arn      = var.retool_db.credentials_secret_id

  # Both names are fixed at creation. Passing the existing names is what stops
  # Terraform from destroying and recreating these resources.
  security_group_name  = var.retool_db.security_group_name
  db_subnet_group_name = var.retool_db.db_subnet_group_name

  # The security group's existing rules are imported and managed in
  # imported-db-rules.tf instead, including the EKS ingress this module would
  # otherwise add. Letting the module manage them would delete every rule it
  # doesn't know about — which is what keeps ECS connected.
  manage_security_group_rules = false

  create_db_parameter_group = var.retool_db.parameter_group_name == null
  parameter_group_name      = var.retool_db.parameter_group_name

  database_name   = var.retool_db.database_name
  master_username = var.retool_db.master_username
  port            = var.retool_db.port

  engine_version        = var.retool_db.engine_version
  instance_class        = var.retool_db.instance_class
  allocated_storage     = var.retool_db.allocated_storage
  max_allocated_storage = var.retool_db.max_allocated_storage
  storage_type          = var.retool_db.storage_type
  iops                  = var.retool_db.iops
  storage_encrypted     = var.retool_db.storage_encrypted
  multi_az              = var.retool_db.multi_az
  family                = var.retool_db.family
  major_engine_version  = var.retool_db.major_engine_version
  deletion_protection   = var.retool_db.deletion_protection
}

# The imported Temporal database, when it is a standalone RDS instance. An
# Aurora cluster cannot be represented by this module — set
# temporal_db_mode = "external" for that and configure temporal_db_external.
module "db-temporal" {
  source = "../../modules/aws-database"
  count  = var.temporal_db_mode == "imported" ? 1 : 0

  prefix     = var.prefix
  db_purpose = "temporal"
  identifier = var.temporal_db.identifier
  tags       = var.tags

  vpc = local.vpc
  eks = module.eks.outputs

  manage_master_user_password = false
  master_user_secret_arn      = var.temporal_db.credentials_secret_id

  security_group_name         = var.temporal_db.security_group_name
  db_subnet_group_name        = var.temporal_db.db_subnet_group_name
  manage_security_group_rules = false

  create_db_parameter_group = var.temporal_db.parameter_group_name == null
  parameter_group_name      = var.temporal_db.parameter_group_name

  database_name   = var.temporal_db.database_name
  master_username = var.temporal_db.master_username
  port            = var.temporal_db.port

  engine_version        = var.temporal_db.engine_version
  instance_class        = var.temporal_db.instance_class
  allocated_storage     = var.temporal_db.allocated_storage
  max_allocated_storage = var.temporal_db.max_allocated_storage
  storage_type          = var.temporal_db.storage_type
  iops                  = var.temporal_db.iops
  storage_encrypted     = var.temporal_db.storage_encrypted
  multi_az              = var.temporal_db.multi_az
  family                = var.temporal_db.family
  major_engine_version  = var.temporal_db.major_engine_version
  deletion_protection   = var.temporal_db.deletion_protection
}

module "retool-services" {
  source = "../../modules/aws-retool-services"

  prefix = var.prefix
  region = var.region
  vpc    = local.vpc
  eks    = module.eks.outputs
  db     = module.db-main.outputs
  tags   = var.tags

  db_password_secret_property = var.retool_db.password_property

  # Carry the existing secrets over rather than generating new ones. The
  # encryption key in particular is load-bearing: every credential stored in the
  # Retool database is encrypted with it.
  encryption_key_secret_name     = var.encryption_key_secret.secret_id
  encryption_key_secret_property = var.encryption_key_secret.property

  jwt_secret_secret_path     = try(var.jwt_secret.secret_id, null)
  jwt_secret_secret_property = try(var.jwt_secret.property, null)

  license_key_secret_path     = try(var.license_key_secret.secret_id, null)
  license_key_secret_property = try(var.license_key_secret.property, null)

  # Lets External Secrets Operator read the Temporal database credentials, which
  # live outside the retool/{prefix}/* namespace. See temporal.tf.
  extra_secret_read_arns = compact([local.temporal_credentials_secret_id])

  enable_agent_sandbox = var.enable_agent_sandbox
  enable_rr_s3         = var.enable_rr_s3

  depends_on = [module.eks]
}

module "retool" {
  source = "../../modules/retool-helm"

  retool_helm_name          = "retool"
  retool_helm_chart_version = var.retool_helm_chart_version

  db              = module.db-main.outputs
  retool_services = module.retool-services.outputs
  domain_name     = var.domain_name

  # The CloudFormation stack terminates TLS at the load balancer and runs with
  # COOKIE_INSECURE=false; https_enabled = true is the equivalent here. It also
  # drives the scheme in BASE_DOMAIN, so it has to track the ingress listener.
  https_enabled = var.enable_https

  # Workflows needs a Temporal cluster, which needs a Temporal database.
  workflows_enabled = local.temporal_enabled

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
  # was supplied — the usual case is that both are managed elsewhere.
  #
  # The CloudFormation stack's own load balancer is deliberately NOT imported:
  # this one runs alongside it, and moving DNS between them is the cutover.
  acm_certificate_arn = var.acm_certificate_arn
  create_hosted_zone  = var.acm_certificate_arn == null && var.hosted_zone_id == null
  hosted_zone_id      = var.hosted_zone_id

  alb_authenticate_oidc = local.alb_authenticate_oidc

  depends_on = [module.retool-services, module.retool]
}
