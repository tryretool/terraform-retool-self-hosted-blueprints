locals {
  prefix      = "blessed-02"
  project_id  = "my-gcp-project" # replace with your GCP project ID
  region      = "us-central1"
  domain_name = "retool.example.com" # replace with your domain
}

module "vpc" {
  source  = "tryretool/self-hosted-blueprints/retool//modules/gcp-vpc"
  version = "~> 0.0.1"

  prefix     = local.prefix
  project_id = local.project_id
  region     = local.region
}

module "gke" {
  source  = "tryretool/self-hosted-blueprints/retool//modules/gcp-gke"
  version = "~> 0.0.1"

  prefix     = local.prefix
  project_id = local.project_id
  region     = local.region
  vpc        = module.vpc.outputs

  depends_on = [module.vpc]
}

module "db-main" {
  source  = "tryretool/self-hosted-blueprints/retool//modules/gcp-database"
  version = "~> 0.0.1"

  prefix     = local.prefix
  project_id = local.project_id
  region     = local.region
  vpc        = module.vpc.outputs
  db_purpose = "main"
  tier       = "db-g1-small"

  # Cloud SQL requires the VPC peering connection (google_service_networking_connection)
  # created by the vpc module's private_service_access submodule to exist before the
  # instance is created. This explicit dependency ensures correct ordering.
  depends_on = [module.vpc]
}

module "retool-services" {
  source  = "tryretool/self-hosted-blueprints/retool//modules/gcp-retool-services"
  version = "~> 0.0.1"

  prefix     = local.prefix
  project_id = local.project_id
  region     = local.region
  gke        = module.gke.outputs
  db         = module.db-main.outputs

  enable_agent_sandbox = true
  enable_rr_git_gcs    = true
  license_key          = "SECRET"

  depends_on = [module.gke]
}

module "user-ingress" {
  source  = "tryretool/self-hosted-blueprints/retool//modules/gcp-user-ingress"
  version = "~> 0.0.1"

  prefix      = local.prefix
  project_id  = local.project_id
  region      = local.region
  domain_name = local.domain_name

  enable_agent_sandbox_proxy = true

  depends_on = [module.gke, module.retool-services]
}

module "retool" {
  source  = "tryretool/self-hosted-blueprints/retool//modules/common/retool-helm"
  version = "~> 0.0.1"

  retool_helm_name                         = "retool"
  retool_helm_chart_version                = "6.11.0"
  retool_helm_chart_use_unpublished_branch = "lfoster/agent-sandbox-support"

  db              = module.db-main.outputs
  retool_services = module.retool-services.outputs

  retool_helm_extra_values = [yamlencode({
    image = {
      repository = "753800337063.dkr.ecr.us-west-2.amazonaws.com/onprem"
      tag        = "dev-3.380.0-940f7d8"
    }
    # Disable the traditional Ingress — the Gateway HTTPRoute handles routing.
    ingress = { enabled = false }
    httpRoute = {
      enabled   = true
      hostnames = [local.domain_name, "*.${local.domain_name}"]
      parentRefs = [{
        name        = module.user-ingress.gateway_name
        namespace   = "default"
        sectionName = "https"
      }]
    }
    env = {
      BASE_DOMAIN = "https://${local.domain_name}"
    }
    replicaCount = 2
    podDisruptionBudget = {
      maxUnavailable = 1
    }
    dbconnector = {
      enabled  = true
      replicas = 2
    }
    r2Agent = {
      enabled = true
    }
    telemetry = {
      enabled = true
      image = {
        tag = "3.334.0-stable"
      }
    }
    workflows = {
      enabled = true
      worker = {
        replicaCount = 2
      }
      backend = {
        replicaCount = 2
      }
    }
    codeExecutor = {
      enabled      = true
      replicaCount = 2
      image = {
        repository = "753800337063.dkr.ecr.us-west-2.amazonaws.com/code-executor-service"
        tag        = "dev-3.380.0-940f7d8"
      }
    }
    jsExecutor = {
      replicaCount = 2
      image = {
        repository = "753800337063.dkr.ecr.us-west-2.amazonaws.com/js-executor-service"
        tag        = "dev-3.380.0-940f7d8"
      }
    }
    agentSandbox = {
      enabled = true
      image = {
        repository = "753800337063.dkr.ecr.us-west-2.amazonaws.com/agent-executor-service"
        tag        = "dev-3.380.0-940f7d8"
      }
      devicePlugin = {
        # GKE requires a custom ResourceQuota to use the default
        # `system-node-critical` PriorityClass, so disable PriorityClass usage
        # for this daemonset.
        priorityClassName = null
      }
      postgres = {
        schema = "agent_executor"
      }
      externalSecret = {
        name = module.retool-services.outputs.agent_sandbox_secret_name
      }
      frontendWsProxyDomain = "https://agent-proxy.${local.domain_name}"
      proxy = {
        backendDomainSuffixes = local.domain_name
        # httpRoute = {
        #   enabled   = true
        #   hostnames = ["agent-proxy.${local.domain_name}"]
        #   parentRefs = [{
        #     name        = module.user-ingress.gateway_name
        #     namespace   = "default"
        #     sectionName = "https"
        #   }]
        # }
      }
    }
  })]

  depends_on = [module.retool-services, module.user-ingress]
}

output "modules" {
  value = {
    vpc             = module.vpc
    gke             = module.gke
    db-main         = module.db-main
    retool-services = module.retool-services
    user-ingress    = module.user-ingress
    retool          = module.retool
  }
}
