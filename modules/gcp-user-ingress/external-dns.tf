locals {
  external_dns = {
    name                 = "external-dns"
    namespace            = "external-dns"
    service_account_name = "external-dns"
  }
}

resource "google_service_account" "external_dns" {
  account_id   = "${var.prefix}-external-dns"
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

# external-dns lists zones to discover them even when the zone filter is set, and
# that permission is project-scoped rather than part of a zone-level binding.
resource "google_project_iam_member" "external_dns_admin" {
  project = var.project_id
  role    = "roles/dns.admin"
  member  = "serviceAccount:${google_service_account.external_dns.email}"
}

resource "helm_release" "external_dns" {
  namespace        = local.external_dns.namespace
  create_namespace = true

  name       = local.external_dns.name
  repository = var.external_dns_chart.repository
  chart      = "external-dns"
  version    = var.external_dns_chart.version
  wait       = true
  timeout    = 600

  values = [yamlencode({
    provider = { name = "google" }

    image = {
      repository = var.external_dns_chart.image_repository
      tag        = var.external_dns_chart.image_tag
    }

    # Watch Gateway HTTPRoute resources for hostnames to publish.
    sources = ["gateway-httproute"]

    # Never delete records — safe default for shared or delegated zones.
    policy = "upsert-only"

    # Unique owner ID so txt records from multiple deployments don't collide.
    txtOwnerId = var.prefix

    serviceAccount = {
      annotations = {
        "iam.gke.io/gcp-service-account" = google_service_account.external_dns.email
      }
    }

    # zone-id-filter has to be passed as a flag. The chart has no zoneIdFilters
    # value and silently drops one, which leaves external-dns free to write to
    # every zone in the project.
    extraArgs = [
      "--google-project=${var.project_id}",
      "--zone-id-filter=${google_dns_managed_zone.main.name}",
    ]
  })]
}
