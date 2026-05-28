locals {
  eso = {
    name                 = "external-secrets"
    namespace            = "external-secrets"
    service_account_name = "external-secrets"
  }

  # Secret name for encryption-key — either user-provided or auto-generated
  encryption_key_secret_ref = (
    var.encryption_key_secret_name != null
    ? var.encryption_key_secret_name
    : "retool-${var.prefix}-encryption-key"
  )
}

resource "google_service_account" "eso" {
  account_id   = "${var.prefix}-eso"
  display_name = "${var.prefix} External Secrets Operator service account"
  project      = var.project_id
}

# var.gke.endpoint is "known after apply" — this resource exists solely to
# carry that dependency into the graph so that eso_workload_identity (below) waits
# until the GKE cluster is up and its Workload Identity pool ({project_id}.svc.id.goog)
# has been created before we try to bind it.
resource "terraform_data" "gke_workload_identity_pool_ready" {
  input = var.gke.endpoint
}

# Workload Identity binding: k8s ServiceAccount external-secrets/external-secrets → GCP SA
resource "google_service_account_iam_binding" "eso_workload_identity" {
  depends_on = [terraform_data.gke_workload_identity_pool_ready]

  service_account_id = google_service_account.eso.name
  role               = "roles/iam.workloadIdentityUser"
  members = [
    "serviceAccount:${var.project_id}.svc.id.goog[${local.eso.namespace}/${local.eso.service_account_name}]"
  ]
}

# Grant ESO read access to each secret individually (least-privilege, no project-level binding)
resource "google_secret_manager_secret_iam_member" "eso_encryption_key" {
  count     = var.encryption_key_secret_name == null ? 1 : 0
  project   = var.project_id
  secret_id = google_secret_manager_secret.encryption_key[0].secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.eso.email}"
}

resource "google_secret_manager_secret_iam_member" "eso_encryption_key_external" {
  count     = var.encryption_key_secret_name != null ? 1 : 0
  project   = var.project_id
  secret_id = var.encryption_key_secret_name
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.eso.email}"
}

resource "google_secret_manager_secret_iam_member" "eso_jwt_secret" {
  project   = var.project_id
  secret_id = google_secret_manager_secret.jwt_secret.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.eso.email}"
}

resource "google_secret_manager_secret_iam_member" "eso_extra_env_vars" {
  project   = var.project_id
  secret_id = google_secret_manager_secret.extra_env_vars.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.eso.email}"
}

resource "google_secret_manager_secret_iam_member" "eso_db_credentials" {
  project   = var.project_id
  secret_id = var.db.master_user_secret_name
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.eso.email}"
}

resource "google_secret_manager_secret_iam_member" "eso_license_key" {
  count     = nonsensitive(var.license_key != null) ? 1 : 0
  project   = var.project_id
  secret_id = google_secret_manager_secret.license_key[0].secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.eso.email}"
}

resource "helm_release" "external_secrets" {
  namespace        = local.eso.namespace
  create_namespace = true

  name       = local.eso.name
  repository = "https://charts.external-secrets.io"
  chart      = "external-secrets"
  version    = "0.12.1"
  wait       = true

  values = [yamlencode({
    installCRDs = true
    serviceAccount = {
      annotations = {
        "iam.gke.io/gcp-service-account" = google_service_account.eso.email
      }
    }
  })]
}

resource "kubectl_manifest" "secret_store" {
  yaml_body = yamlencode({
    apiVersion = "external-secrets.io/v1beta1"
    kind       = "ClusterSecretStore"
    metadata = {
      name = "gcp-secretsmanager"
    }
    spec = {
      provider = {
        gcpsm = {
          projectID = var.project_id
          auth = {
            workloadIdentity = {
              clusterLocation  = var.gke.location
              clusterName      = var.gke.name
              clusterProjectID = var.project_id
              serviceAccountRef = {
                name      = local.eso.service_account_name
                namespace = local.eso.namespace
              }
            }
          }
        }
      }
    }
  })

  depends_on = [helm_release.external_secrets]
}

locals {
  retool_namespace = "default"

  external_secrets = concat(
    [
      {
        name = "encryption-key"
        data = [{
          secretKey = "encryption-key"
          remoteRef = { key = local.encryption_key_secret_ref }
        }]
        target_deletion_policy = "Retain"
      },
      {
        name = "jwt-secret"
        data = [{
          secretKey = "jwt-secret"
          remoteRef = { key = "retool-${var.prefix}-jwt-secret" }
        }]
        target_deletion_policy = "Retain"
      },
      {
        name = "db-credentials"
        data = [{
          secretKey = "password"
          remoteRef = { key = var.db.master_user_secret_name }
        }]
        target_deletion_policy = "Retain"
      },
    ],
    nonsensitive(var.license_key != null) ? [
      {
        name = "license-key"
        data = [{
          secretKey = "license-key"
          remoteRef = { key = "retool-${var.prefix}-license-key" }
        }]
        target_deletion_policy = "Retain"
      },
    ] : [],
  )
}

resource "kubectl_manifest" "external_secret" {
  for_each = { for s in local.external_secrets : s.name => s }

  yaml_body = yamlencode({
    apiVersion = "external-secrets.io/v1beta1"
    kind       = "ExternalSecret"
    metadata = {
      name      = each.value.name
      namespace = local.retool_namespace
    }
    spec = {
      refreshInterval = "1m"
      secretStoreRef = {
        kind = "ClusterSecretStore"
        name = "gcp-secretsmanager"
      }
      target = {
        name           = each.value.name
        creationPolicy = "Owner"
        deletionPolicy = each.value.target_deletion_policy
      }
      data = each.value.data
    }
  })

  depends_on = [kubectl_manifest.secret_store]
}

resource "kubectl_manifest" "external_secret_extra_env_vars" {
  yaml_body = yamlencode({
    apiVersion = "external-secrets.io/v1beta1"
    kind       = "ExternalSecret"
    metadata = {
      name      = "extra-env-vars"
      namespace = local.retool_namespace
    }
    spec = {
      refreshInterval = "1m"
      secretStoreRef = {
        kind = "ClusterSecretStore"
        name = "gcp-secretsmanager"
      }
      target = {
        name           = "extra-env-vars"
        creationPolicy = "Owner"
        deletionPolicy = "Merge"
      }
      dataFrom = [{
        extract = {
          key = "retool-${var.prefix}-extra-env-vars"
        }
      }]
    }
  })

  depends_on = [kubectl_manifest.secret_store]
}

resource "kubectl_manifest" "external_secret_agent_sandbox" {
  count = var.enable_agent_sandbox ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "external-secrets.io/v1beta1"
    kind       = "ExternalSecret"
    metadata = {
      name      = "agent-sandbox"
      namespace = local.retool_namespace
    }
    spec = {
      refreshInterval = "1m"
      secretStoreRef = {
        kind = "ClusterSecretStore"
        name = "gcp-secretsmanager"
      }
      target = {
        name           = "agent-sandbox"
        creationPolicy = "Owner"
        deletionPolicy = "Retain"
      }
      dataFrom = [{
        extract = {
          key = "retool-${var.prefix}-agent-sandbox"
        }
      }]
    }
  })

  depends_on = [kubectl_manifest.secret_store]
}

resource "kubectl_manifest" "external_secret_rr_gcs" {
  count = var.enable_rr_gcs ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "external-secrets.io/v1beta1"
    kind       = "ExternalSecret"
    metadata = {
      name      = "rr-gcs-credentials"
      namespace = local.retool_namespace
    }
    spec = {
      refreshInterval = "1m"
      secretStoreRef = {
        kind = "ClusterSecretStore"
        name = "gcp-secretsmanager"
      }
      target = {
        name           = "rr-gcs-credentials"
        creationPolicy = "Owner"
        deletionPolicy = "Retain"
      }
      dataFrom = [{
        extract = {
          key = "retool-${var.prefix}-rr-gcs"
        }
      }]
    }
  })

  depends_on = [kubectl_manifest.secret_store]
}
