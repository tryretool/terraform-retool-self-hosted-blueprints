# Self-hosted Temporal, required by Retool Workflows.
#
# The CloudFormation stack ran Temporal as five separate ECS services. On
# Kubernetes the Retool Helm chart runs the whole Temporal cluster itself through
# its bundled retool-temporal-services-helm subchart, so only the database
# carries over — either imported into module.db-temporal, or referenced in place
# when it is an Aurora cluster the aws-database module cannot represent.
#
# The chart wires WORKFLOW_TEMPORAL_CLUSTER_FRONTEND_HOST automatically when the
# subchart is enabled, so no service discovery config is needed (the
# CloudFormation stack's Cloud Map namespace has no equivalent here).

locals {
  temporal_enabled = var.temporal_db_mode != "none"

  # Connection details, from whichever source is in play.
  temporal_connection = (
    var.temporal_db_mode == "imported" ? {
      host     = module.db-temporal[0].outputs.address
      port     = module.db-temporal[0].outputs.port
      username = module.db-temporal[0].outputs.username
      database = var.temporal_db.database_name
      } : var.temporal_db_mode == "external" ? {
      host     = var.temporal_db_external.host
      port     = var.temporal_db_external.port
      username = var.temporal_db_external.username
      database = "temporal"
    } : null
  )

  temporal_credentials_secret_id = (
    var.temporal_db_mode == "imported" ? var.temporal_db.credentials_secret_id
    : var.temporal_db_mode == "external" ? var.temporal_db_external.credentials_secret_id
    : null
  )

  temporal_password_property = (
    var.temporal_db_mode == "imported" ? var.temporal_db.password_property
    : var.temporal_db_mode == "external" ? var.temporal_db_external.password_property
    : null
  )

  # Kubernetes Secret the Temporal subchart reads the database password from.
  temporal_db_secret_name = "temporal-db-credentials"
  temporal_db_secret_key  = "password"

  temporal_sql_common = local.temporal_enabled ? {
    host           = local.temporal_connection.host
    port           = local.temporal_connection.port
    user           = local.temporal_connection.username
    existingSecret = local.temporal_db_secret_name
    secretKey      = local.temporal_db_secret_key
    tls = {
      enabled = var.temporal.tls_enabled
      # RDS and Aurora present certificates for their own endpoint hostnames,
      # signed by the Amazon RDS CA rather than a public root, so the client
      # encrypts without verifying the hostname. This matches the
      # POSTGRES_SSL_ENABLED behaviour of the Retool backend.
      enableHostVerification = false
    }
  } : null

  temporal_values = local.temporal_enabled ? [yamlencode({
    "retool-temporal-services-helm" = {
      enabled = true
      server = {
        image = {
          repository = var.temporal.image_repository
          tag        = var.temporal.image_tag
        }
        config = {
          persistence = {
            default = {
              sql = merge(local.temporal_sql_common, {
                database = local.temporal_connection.database
              })
            }
            visibility = {
              sql = merge(local.temporal_sql_common, {
                database = var.temporal.visibility_database
              })
            }
          }
          numHistoryShards = var.temporal.num_history_shards
        }
      }
      # The Temporal Web UI, for inspecting running workflows. Not exposed
      # outside the cluster — reach it with `kubectl port-forward`.
      web = {
        enabled = var.temporal.enable_web_ui
      }
    }
  })] : []
}

# Syncs the Temporal database password from Secrets Manager into the cluster.
# The retool-services module creates the equivalent for the main Retool database
# but knows nothing about this second one, so it is declared here — with the
# secret's ARN passed to that module via extra_secret_read_arns so External
# Secrets Operator is permitted to read it.
resource "kubectl_manifest" "temporal_db_credentials" {
  count = local.temporal_enabled ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "external-secrets.io/v1beta1"
    kind       = "ExternalSecret"
    metadata = {
      name      = local.temporal_db_secret_name
      namespace = "default"
    }
    spec = {
      refreshInterval = "1m"
      secretStoreRef = {
        kind = "ClusterSecretStore"
        name = "aws-secretsmanager"
      }
      target = {
        name           = local.temporal_db_secret_name
        creationPolicy = "Owner"
        deletionPolicy = "Retain"
      }
      data = [{
        secretKey = local.temporal_db_secret_key
        remoteRef = {
          key      = local.temporal_credentials_secret_id
          property = local.temporal_password_property
        }
      }]
    }
  })

  depends_on = [module.retool-services]
}
