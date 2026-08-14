# Self-hosted Temporal, required by Retool Workflows.
#
# The CloudFormation stack ran Temporal as five separate ECS services against a
# dedicated Aurora cluster. On Kubernetes the Retool Helm chart runs the whole
# Temporal cluster itself through its bundled retool-temporal-services-helm
# subchart, so only the database is carried over — pointed at by var.temporal.
#
# The chart wires WORKFLOW_TEMPORAL_CLUSTER_FRONTEND_HOST automatically when the
# subchart is enabled, so no service discovery config is needed (the
# CloudFormation stack's Cloud Map namespace has no equivalent here).

locals {
  temporal_enabled = var.temporal != null

  # Kubernetes Secret the Temporal subchart reads the database password from.
  temporal_db_secret_name = "temporal-db-credentials"
  temporal_db_secret_key  = "password"

  temporal_sql_common = local.temporal_enabled ? {
    host           = var.temporal.host
    port           = var.temporal.port
    user           = var.temporal.username
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
                database = var.temporal.database
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
          key      = var.temporal.credentials_secret_id
          property = var.temporal.password_property
        }
      }]
    }
  })

  depends_on = [module.retool-services]
}

# As with the main database, the Temporal cluster's security group admits the
# CloudFormation stack's ECS tasks but not the new EKS nodes.
resource "aws_vpc_security_group_ingress_rule" "temporal_db_from_eks_nodes" {
  count = local.temporal_enabled && try(var.temporal.security_group_id, null) != null ? 1 : 0

  security_group_id            = var.temporal.security_group_id
  description                  = "Postgres from ${local.cluster_name} EKS nodes (Temporal)"
  referenced_security_group_id = module.eks.outputs.node_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = var.temporal.port
  to_port                      = var.temporal.port
}
