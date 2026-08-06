locals {
  eso = {
    name                 = "external-secrets"
    namespace            = "external-secrets"
    service_account_name = "external-secrets"
  }

  eso_image = {
    repository = var.external_secrets_chart.image_repository
    tag        = var.external_secrets_chart.image_tag
  }

  # Secret name for encryption-key — either user-provided or auto-generated
  encryption_key_secret_ref = (
    var.encryption_key_secret_name != null
    ? var.encryption_key_secret_name
    : "retool-${var.prefix}-encryption-key"
  )

  # Secret Manager key for the license key, sourced from either the managed
  # secret (var.license_key) or an existing one (var.license_key_secret_path).
  # null when neither is set (free-tier mode).
  license_key_remote_ref = (
    nonsensitive(var.license_key != null)
    ? "retool-${var.prefix}-license-key"
    : var.license_key_secret_path
  )
}

resource "google_service_account" "eso" {
  account_id   = substr("${var.prefix}-eso", 0, 30)
  display_name = "${var.prefix} External Secrets Operator service account"
  project      = var.project_id
}

# var.gke.endpoint is "known after apply" — this resource exists solely to
# carry that dependency into the graph so that eso_workload_identity (below) waits
# until the GKE cluster is up and its Workload Identity pool ({project_id}.svc.id.goog)
# has been created before we try to bind it.
#
# null_resource rather than terraform_data because GCP Marketplace rejects the
# builtin terraform provider that terraform_data comes from.
resource "null_resource" "gke_workload_identity_pool_ready" {
  triggers = {
    endpoint = var.gke.endpoint
  }
}

# Workload Identity binding: k8s ServiceAccount external-secrets/external-secrets → GCP SA
resource "google_service_account_iam_binding" "eso_workload_identity" {
  depends_on = [null_resource.gke_workload_identity_pool_ready]

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

# When the license key lives in a pre-existing secret, grant ESO read access to
# that secret instead of a managed one.
resource "google_secret_manager_secret_iam_member" "eso_license_key_external" {
  count     = var.license_key_secret_path != null ? 1 : 0
  project   = var.project_id
  secret_id = var.license_key_secret_path
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.eso.email}"
}

resource "helm_release" "external_secrets" {
  namespace        = local.eso.namespace
  create_namespace = true

  name       = local.eso.name
  repository = var.external_secrets_chart.repository
  chart      = "external-secrets"
  version    = var.external_secrets_chart.version
  wait       = true

  values = [yamlencode({
    installCRDs = true

    # The operator, webhook and cert-controller are three deployments running the
    # same image, each reading its own values block. Setting only the top one
    # leaves the other two pulling from upstream.
    image          = local.eso_image
    certController = { image = local.eso_image }

    webhook = {
      image = local.eso_image

      # Terraform destroys the node pool before these releases, so the webhook
      # pods are gone by the time the CRs are deleted. Under the default Fail
      # policy the unreachable webhook rejects those deletes and the destroy
      # hangs. From 2.8.0 the chart wires this into every validating webhook,
      # including `secretstore-validate`, which earlier versions left at Fail.
      failurePolicy = "Ignore"
    }

    serviceAccount = {
      annotations = {
        "iam.gke.io/gcp-service-account" = google_service_account.eso.email
      }
    }
  })]
}

# The External Secrets CRs are applied through Helm because GCP Marketplace
# permits neither gavinbunney/kubectl nor kubernetes_manifest here. See
# chart/Chart.yaml for why.
#
# The store is its own release so it's created before the ExternalSecrets that
# reference it, rather than leaning on how Helm happens to order unknown kinds.
resource "helm_release" "secret_store" {
  name      = "${var.prefix}-secret-store"
  namespace = local.retool_namespace
  chart     = "${path.module}/chart"

  values = [yamlencode({
    manifests = [{
      apiVersion = "external-secrets.io/v1"
      kind       = "ClusterSecretStore"
      metadata = {
        name = local.secret_store_ref.name
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
    }]
  })]

  depends_on = [helm_release.external_secrets]
}

locals {
  retool_namespace = "default"

  secret_store_ref = {
    kind = "ClusterSecretStore"
    name = "gcp-secretsmanager"
  }

  # ExternalSecrets that map named Secret Manager secrets to individual keys.
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
    local.license_key_remote_ref != null ? [
      {
        name = "license-key"
        data = [{
          secretKey = "license-key"
          remoteRef = { key = local.license_key_remote_ref }
        }]
        target_deletion_policy = "Retain"
      },
    ] : [],
  )

  # ExternalSecrets that expand every key of a JSON secret. extra-env-vars uses
  # Merge so keys written into the target Secret by other means survive a refresh.
  external_secrets_extract = concat(
    [
      {
        name                   = "extra-env-vars"
        remote_key             = "retool-${var.prefix}-extra-env-vars"
        target_deletion_policy = "Merge"
      },
    ],
    var.enable_agent_sandbox ? [
      {
        name                   = "agent-sandbox"
        remote_key             = "retool-${var.prefix}-agent-sandbox"
        target_deletion_policy = "Retain"
      },
    ] : [],
    var.enable_rr_gcs ? [
      {
        name                   = "rr-gcs-credentials"
        remote_key             = "retool-${var.prefix}-rr-gcs"
        target_deletion_policy = "Retain"
      },
    ] : [],
  )

  external_secret_manifests = concat(
    [for s in local.external_secrets : {
      apiVersion = "external-secrets.io/v1"
      kind       = "ExternalSecret"
      metadata = {
        name      = s.name
        namespace = local.retool_namespace
      }
      spec = {
        refreshInterval = "1m"
        secretStoreRef  = local.secret_store_ref
        target = {
          name           = s.name
          creationPolicy = "Owner"
          deletionPolicy = s.target_deletion_policy
        }
        data = s.data
      }
    }],
    [for s in local.external_secrets_extract : {
      apiVersion = "external-secrets.io/v1"
      kind       = "ExternalSecret"
      metadata = {
        name      = s.name
        namespace = local.retool_namespace
      }
      spec = {
        refreshInterval = "1m"
        secretStoreRef  = local.secret_store_ref
        target = {
          name           = s.name
          creationPolicy = "Owner"
          deletionPolicy = s.target_deletion_policy
        }
        dataFrom = [{ extract = { key = s.remote_key } }]
      }
    }],
  )
}

resource "helm_release" "external_secret_crs" {
  name      = "${var.prefix}-external-secrets"
  namespace = local.retool_namespace
  chart     = "${path.module}/chart"

  values = [yamlencode({ manifests = local.external_secret_manifests })]

  depends_on = [helm_release.secret_store]
}
