locals {
  defaults_values = [yamlencode({
    postgresql = {
      enabled = false
    }
    env = {
      IGNORE_CODE_EXECUTOR_STARTUP_CHECK = "true"
    }
  })]

  secrets_values = (var.db != null && var.retool_services != null) ? [yamlencode({
    config = {
      encryptionKeySecretName = var.retool_services.encryption_key_secret_name
      jwtSecretSecretName     = var.retool_services.jwt_secret_name
      postgresql = {
        host               = var.db.address
        port               = var.db.port
        db                 = var.db.name
        user               = var.db.username
        ssl_enabled        = true
        passwordSecretName = var.retool_services.db_credentials_secret_name
        passwordSecretKey  = var.retool_services.db_credentials_secret_key
      }
    }
    externalSecrets = {
      enabled              = true
      includeConfigSecrets = true
      name                 = var.retool_services.extra_env_vars_secret_name
    }
    # Agent sandbox gets enabled elsewhere, but we preconfigure it here to use
    # the same DB password secret when enabled. This is key for AWS where RDS
    # automatically rotates the password in the master credentials secret, so
    # referencing it this way ensures the agent sandbox credentials stay in
    # sync.
    rr = {
      agentSandbox = {
        postgres = {
          schema             = "agent_executor"
          passwordSecretName = var.retool_services.db_credentials_secret_name
          passwordSecretKey  = var.retool_services.db_credentials_secret_key
        }
      }
    }
  })] : []

  license_values = (
    var.retool_services != null && var.retool_services.license_key_secret_name != null
    ) ? [yamlencode({
      config = {
        licenseKeySecretName = var.retool_services.license_key_secret_name
        licenseKeySecretKey  = var.retool_services.license_key_secret_key
      }
  })] : []

  default_published_repository = "https://charts.retool.com"
  default_repository = (
    var.retool_helm_chart_use_unpublished_branch == null
    ? local.default_published_repository
    : "git+https://github.com/tryretool/retool-helm@charts/retool?ref=${var.retool_helm_chart_use_unpublished_branch}&sparse=1"
  )
  repository = coalesce(var.retool_helm_chart_repository, local.default_repository)

  rr_bucket_values = (var.retool_services != null && var.retool_services.rr_bucket_k8s_secret_name != null) ? [yamlencode({
    env = {
      for key in var.retool_services.rr_bucket_env_keys : key => {
        valueFrom = {
          secretKeyRef = {
            name = var.retool_services.rr_bucket_k8s_secret_name
            key  = key
          }
        }
      }
    }
  })] : []

  url_scheme = var.https_enabled ? "https" : "http"

  domain_values = var.domain_name != null ? [yamlencode({
    config = {
      useInsecureCookies = !var.https_enabled
    }
    env = {
      BASE_DOMAIN = "${local.url_scheme}://${var.domain_name}"
    }
    rr = {
      agentSandbox = {
        proxy = {
          backendDomainSuffixes = var.domain_name
        }
      }
    }
  })] : []

  agent_sandbox_enabled = var.retool_services != null && var.retool_services.agent_sandbox_enabled
  app_hostnames_enabled = var.retool_services != null && var.retool_services.app_hostnames_enabled

  # 6.13.2 is the first published chart with rr.appServingLayer and wildcardSandboxes.
  # Versions this can't parse, such as a git ref, pass.
  chart_version_parts        = try([for part in split(".", split("-", var.retool_helm_chart_version)[0]) : tonumber(part)], null)
  chart_supports_apps_domain = try(local.chart_version_parts[0] * 1000000 + local.chart_version_parts[1] * 1000 + local.chart_version_parts[2] >= 6013002, true)

  # The ingress modules build certificates, DNS and routes for apps.<domain_name> only,
  # so a hostname set in the extra values would have none of them.
  extra_values_set_apps_hostnames = anytrue([
    for values in var.retool_helm_extra_values :
    try(yamldecode(values).rr.appServingLayer.domain, null) != null
    || try(yamldecode(values).rr.agentSandbox.frontendWildcardDomain, null) != null
  ])

  agent_sandbox_values = local.agent_sandbox_enabled ? [yamlencode({
    rr = {
      enabled = true
      agentSandbox = merge(
        {
          enabled = true
          externalSecret = {
            name = var.retool_services.agent_sandbox_secret_name
          }
        },
        # GKE's default ResourceQuota rejects pods that use the
        # `system-node-critical` PriorityClass without an explicit quota
        # carve-out, so for the agent sandbox device plugin DaemonSet on GKE we
        # unset priorityClassName.
        var.retool_services.secret_store_backend_type == "gcpSecretsManager" ? {
          devicePlugin = {
            priorityClassName = null
          }
        } : {},
      )
      jsExecutor = {
        enabled = true
      }
      agent = {
        enabled = true
      }
      gitServer = {
        enabled = var.retool_services.rr_bucket_k8s_secret_name != null
      }
    }
  })] : []

  # A precondition on the release requires domain_name; the null check stops this
  # interpolation from failing first and hiding that message.
  apps_domain_values = local.app_hostnames_enabled && var.domain_name != null ? [yamlencode({
    rr = {
      appServingLayer = {
        enabled = true
        domain  = "apps.${var.domain_name}"
      }
      agentSandbox = {
        wildcardSandboxes = true
      }
    }
  })] : []

  # Namespace precedence: explicit var.namespace, then the namespace exported by
  # retool-services (so the app lands beside its ExternalSecrets), then "default".
  namespace = coalesce(var.namespace, try(var.retool_services.retool_namespace, null), "default")

  workflows_values = [yamlencode({
    workflows = {
      enabled = var.workflows_enabled
    }
  })]

  dbconnector_values = [yamlencode({
    dbconnector = {
      enabled = var.dbconnector_enabled
    }
  })]

  telemetry_values = [yamlencode({
    telemetry = {
      enabled = var.telemetry_enabled
      sendToRetool = {
        enabled = var.telemetry_send_to_retool
        inputs  = var.telemetry_send_to_retool_inputs
      }
    }
  })]

  # Top-level scheduling is inherited by most services; the agent sandbox pods
  # have their own override (which only falls back to global when unset), so set
  # it explicitly when the agent sandbox is enabled.
  pod_scheduling_values = local.has_pod_scheduling ? [yamlencode(merge(
    local.pod_scheduling,
    local.agent_sandbox_enabled ? { rr = { agentSandbox = local.pod_scheduling } } : {},
  ))] : []

  # Self-hosted-blueprints release this module ships as. The single VERSION
  # file lives at the repo root; registry and git module consumers both
  # vendor the whole repo, so ../../VERSION resolves inside the fetched
  # package. `make release-prep` keeps the file in sync with the tag.
  blueprints_version = trimspace(file("${path.module}/../../VERSION"))

  # Deployment template identity reported by the Retool Helm chart via the
  # DEPLOYMENT_TEMPLATE_TYPE env var, e.g. "blueprint-aws-eks-helm/0.5.3".
  # Listed last in the Helm values below so it cannot be overridden or drifted
  # via other values.
  deployment_template_type = (
    var.retool_services != null && var.retool_services.deployment_template_type != null
    ? "blueprint-${var.retool_services.deployment_template_type}-helm/${local.blueprints_version}"
    : null
  )

  deployment_template_values = local.deployment_template_type != null ? [yamlencode({
    deploymentTemplateType = local.deployment_template_type
  })] : []
}

resource "helm_release" "retool" {
  name       = var.retool_helm_name
  repository = local.repository
  chart      = "retool"
  version    = var.retool_helm_chart_version
  namespace  = local.namespace
  timeout    = var.retool_helm_timeout

  values = concat(
    local.defaults_values,
    local.secrets_values,
    local.license_values,
    local.rr_bucket_values,
    local.domain_values,
    local.agent_sandbox_values,
    local.apps_domain_values,
    local.workflows_values,
    local.dbconnector_values,
    local.user_ingress_values,
    local.telemetry_values,
    local.pod_scheduling_values,
    var.retool_helm_extra_values,
    local.deployment_template_values,
  )

  lifecycle {
    # The serving layer reads published apps from the git server's bucket, and this
    # module only turns the git server on alongside the agent sandbox.
    precondition {
      condition = !local.app_hostnames_enabled || (
        var.domain_name != null
        && local.agent_sandbox_enabled
        && try(var.retool_services.rr_bucket_k8s_secret_name, null) != null
      )
      error_message = "enable_app_hostnames on retool-services needs domain_name here, plus enable_agent_sandbox and R² storage on retool-services (the chart's app serving layer requires the R² git server)."
    }

    # Older charts ignore the apps values, leaving the ingress modules' routes with
    # no Services behind them.
    precondition {
      condition     = !local.app_hostnames_enabled || local.chart_supports_apps_domain
      error_message = "enable_app_hostnames on retool-services needs retool_helm_chart_version 6.13.2 or later."
    }

    # The chart moves every editor preview to the sandbox hostnames, so the
    # user-ingress module must have built their certificates, DNS and routes.
    # Callers that route traffic themselves pass no user_ingress.
    precondition {
      condition     = !local.app_hostnames_enabled || var.user_ingress == null || coalesce(var.user_ingress.app_hostnames_enabled, false)
      error_message = "enable_app_hostnames on retool-services needs the user-ingress module to build the app and sandbox routes: pass retool_services = module.retool-services.outputs to the user-ingress module."
    }

    precondition {
      condition     = !local.app_hostnames_enabled || !local.extra_values_set_apps_hostnames
      error_message = "enable_app_hostnames on retool-services serves apps at apps.<domain_name>, so retool_helm_extra_values can't set rr.appServingLayer.domain or rr.agentSandbox.frontendWildcardDomain. To pick your own hostnames, deploy with the Helm chart directly."
    }
  }
}
