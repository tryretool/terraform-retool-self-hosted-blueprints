locals {
  prefix = "blueprint-03"
  region = "us-west-2"
}

module "vpc" {
  source = "../../modules/aws/vpc"
  prefix = local.prefix
}

module "eks" {
  source = "../../modules/aws/eks"
  prefix = local.prefix
  region = local.region
  vpc    = module.vpc.outputs

  default_allowed_instance_families = ["t3", "t3a", "m7i", "m7a"]
}

module "db-main" {
  source     = "../../modules/aws/database"
  prefix     = local.prefix
  db_purpose = "main"

  instance_class        = "db.t3.micro"
  allocated_storage     = 20
  max_allocated_storage = 40

  vpc = module.vpc.outputs
  eks = module.eks.outputs

  backup_retention_period = 1
  deletion_protection     = false
  monitoring_interval     = 0
  create_monitoring_role  = false
}

module "retool-services" {
  source = "../../modules/aws/retool-services"
  prefix = local.prefix
  region = local.region
  vpc    = module.vpc.outputs
  eks    = module.eks.outputs
  db     = module.db-main.outputs
}

module "retool" {
  source                    = "../../modules/common/retool-helm"
  retool_helm_name          = "retool"
  retool_helm_chart_version = "6.8.1"
  db                        = module.db-main.outputs
  retool_services           = module.retool-services.outputs
  retool_helm_extra_values = [yamlencode({
    image = {
      tag = "3.334.0-stable"
    }
    # PLACEHOLDER: For production, set useInsecureCookies = false and configure
    # TLS termination on the ALB. Set BASE_DOMAIN to the real hostname.
    config = {
      useInsecureCookies = true
    }
    ingress = {
      enabled = true
      annotations = {
        "kubernetes.io/ingress.class"                = "alb"
        "alb.ingress.kubernetes.io/scheme"           = "internet-facing"
        "alb.ingress.kubernetes.io/target-type"      = "ip"
        "alb.ingress.kubernetes.io/listen-ports"     = "[{\"HTTP\": 80}]"
        "alb.ingress.kubernetes.io/healthcheck-path" = "/api/checkHealth"
        "alb.ingress.kubernetes.io/healthcheck-port" = "3000"
      }
      hosts = [
        {
          host  = ""
          paths = [{ path = "/*" }]
        }
      ]
    }
    # PLACEHOLDER: Replace BASE_DOMAIN with the real hostname before production
    # use. COOKIE_INSECURE should be "false" once TLS is configured.
    env = {
      BASE_DOMAIN                        = "http://localhost"
      COOKIE_INSECURE                    = "true"
      IGNORE_CODE_EXECUTOR_STARTUP_CHECK = "true"
    }
    replicaCount = 1
    workflows = {
      enabled = false
    }
    codeExecutor = {
      enabled = false
    }
  })]

  depends_on = [module.retool-services]
}
