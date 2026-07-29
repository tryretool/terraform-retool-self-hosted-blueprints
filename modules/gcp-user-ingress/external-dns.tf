locals {
  external_dns = {
    name                 = "external-dns"
    namespace            = "external-dns"
    service_account_name = "external-dns"
  }
}

resource "google_service_account" "external_dns" {
  account_id   = substr("${var.prefix}-external-dns", 0, 30)
  display_name = "${var.prefix} external-dns service account"
  project      = var.project_id
}

# Workload Identity binding: k8s SA external-dns/external-dns → GCP SA.
# Mirrors the ESO Workload Identity pattern in the retool-services module.
resource "google_service_account_iam_binding" "external_dns_workload_identity" {
  service_account_id = google_service_account.external_dns.name
  role               = "roles/iam.workloadIdentityUser"
  members = [
    "serviceAccount:${var.project_id}.svc.id.goog[${local.external_dns.namespace}/${local.external_dns.service_account_name}]"
  ]
}

# external-dns needs dns.managedZones.list to discover zones even when zoneIdFilters
# is set — that permission is project-scoped and not included in zone-level bindings.
# roles/dns.admin at the project level covers all required operations.
resource "google_project_iam_member" "external_dns_admin" {
  project = var.project_id
  role    = "roles/dns.admin"
  member  = "serviceAccount:${google_service_account.external_dns.email}"
}

resource "helm_release" "external_dns" {
  namespace        = local.external_dns.namespace
  create_namespace = true

  name       = local.external_dns.name
  repository = "https://kubernetes-sigs.github.io/external-dns/"
  chart      = "external-dns"
  version    = "1.15.0"
  wait       = true
  timeout    = 600

  values = [yamlencode({
    provider = { name = "google" }

    # Watch Gateway HTTPRoute resources for hostnames to publish.
    sources = ["gateway-httproute"]

    # Scope to this zone by ID rather than filtering by domain string.
    zoneIdFilters = [google_dns_managed_zone.main.name]

    # Never delete records — safe default for shared or delegated zones.
    policy = "upsert-only"

    # Unique owner ID so txt records from multiple deployments don't collide.
    txtOwnerId = var.prefix

    serviceAccount = {
      annotations = {
        "iam.gke.io/gcp-service-account" = google_service_account.external_dns.email
      }
    }

    extraArgs = ["--google-project=${var.project_id}"]
  })]
}
