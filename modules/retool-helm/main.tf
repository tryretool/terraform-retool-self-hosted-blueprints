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
  })] : []

  license_values = (
    var.retool_services != null && var.retool_services.license_key_secret_name != null
    ) ? [yamlencode({
      config = {
        licenseKeySecretName = var.retool_services.license_key_secret_name
      }
  })] : []

  repository = (
    var.retool_helm_chart_use_unpublished_branch == null
    ? "https://charts.retool.com"
    : "git+https://github.com/tryretool/retool-helm@charts/retool?ref=${var.retool_helm_chart_use_unpublished_branch}&sparse=1"
  )

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
    agentSandbox = {
      proxy = {
        backendDomainSuffixes = var.domain_name
      }
    }
  })] : []

  agent_sandbox_enabled = var.retool_services != null && var.retool_services.agent_sandbox_enabled

  agent_sandbox_values = local.agent_sandbox_enabled ? [yamlencode({
    r2 = {
      enabled = true
    }
    agentSandbox = merge(
      {
        enabled = true
        postgres = {
          schema = "agent_executor"
        }
        externalSecret = {
          name = var.retool_services.agent_sandbox_secret_name
        }
      },
      # GKE's default ResourceQuota rejects pods that use the
      # `system-node-critical` PriorityClass without an explicit quota
      # carve-out, so for the agent sandbox device plugin DaemonSet on GKE we
      # unset priorityClassName.
      var.retool_services.backend_type == "gcpSecretsManager" ? {
        devicePlugin = {
          priorityClassName = null
        }
      } : {},
    )
    jsExecutor = {
      enabled = true
    }
    r2Agent = {
      enabled = true
    }
  })] : []

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
}

resource "helm_release" "retool" {
  name       = var.retool_helm_name
  repository = local.repository
  chart      = "retool"
  version    = var.retool_helm_chart_version
  namespace  = "default"
  # Full-stack deploys (workflows, code executor) can take longer than 5m for
  # all Deployments to become ready; a short timeout causes terraform apply to fail
  # even when the release eventually succeeds.
  timeout = 20 * 60

  values = concat(
    local.defaults_values,
    local.secrets_values,
    local.license_values,
    local.rr_bucket_values,
    local.domain_values,
    local.agent_sandbox_values,
    local.workflows_values,
    local.dbconnector_values,
    local.user_ingress_values,
    var.retool_helm_extra_values,
  )

  lifecycle {
    # The Helm provider treats `timeout` as a replace-triggering attribute; bumping it
    # would otherwise destroy/recreate the release on upgrade. Ignore post-create
    # changes so we only set the longer wait window on initial install.
    ignore_changes = [timeout]
  }
}
