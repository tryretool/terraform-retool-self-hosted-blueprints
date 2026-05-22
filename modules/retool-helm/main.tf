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
    environmentSecrets = [
      for key in var.retool_services.rr_bucket_env_keys : {
        name = key
        secretKeyRef = {
          name = var.retool_services.rr_bucket_k8s_secret_name
          key  = key
        }
      }
    ]
  })] : []
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

  values = concat(local.defaults_values, local.secrets_values, local.license_values, local.rr_bucket_values, var.retool_helm_extra_values)

  lifecycle {
    # The Helm provider treats `timeout` as a replace-triggering attribute; bumping it
    # would otherwise destroy/recreate the release on upgrade. Ignore post-create
    # changes so we only set the longer wait window on initial install.
    ignore_changes = [timeout]
  }
}
