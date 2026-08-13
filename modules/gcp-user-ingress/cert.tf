# DNS authorization issues a CNAME challenge that Terraform installs into the zone.
# This is the GCP equivalent of ACM's DNS validation flow: the cert is validated
# out-of-band by GCP once the CNAME record propagates, with no polling required.
resource "google_certificate_manager_dns_authorization" "main" {
  depends_on = [google_project_service.certificatemanager]

  name        = "${var.prefix}-cert-auth"
  description = "DNS authorization for Retool managed certificate (also covers wildcard)"
  domain      = var.domain_name
  project     = var.project_id
  labels      = local.all_labels
}

# CNAME challenge record — equivalent to aws_route53_record cert_validation
resource "google_dns_record_set" "cert_validation" {
  name         = google_certificate_manager_dns_authorization.main.dns_resource_record[0].name
  type         = google_certificate_manager_dns_authorization.main.dns_resource_record[0].type
  ttl          = 60
  managed_zone = google_dns_managed_zone.main.name
  project      = var.project_id
  rrdatas      = [google_certificate_manager_dns_authorization.main.dns_resource_record[0].data]
}

# Google-managed certificate, DNS-validated via the authorizations above.
# Equivalent to aws_acm_certificate; GCP provisions and renews it automatically.
# Covers both the base domain and the wildcard (*.domain_name).
resource "google_certificate_manager_certificate" "main" {
  name        = "${var.prefix}-cert"
  description = "Google-managed certificate for Retool"
  project     = var.project_id
  labels      = local.all_labels

  managed {
    domains = [var.domain_name, "*.${var.domain_name}"]
    dns_authorizations = [
      google_certificate_manager_dns_authorization.main.id,
    ]
  }
}

# Certificate map — the object that Gateway references via the certmap annotation.
resource "google_certificate_manager_certificate_map" "main" {
  name    = "${var.prefix}-cert-map"
  project = var.project_id
  labels  = local.all_labels
}

resource "google_certificate_manager_certificate_map_entry" "main" {
  name         = "${var.prefix}-cert-map-entry"
  map          = google_certificate_manager_certificate_map.main.name
  certificates = [google_certificate_manager_certificate.main.id]
  hostname     = var.domain_name
  project      = var.project_id
  labels       = local.all_labels
  lifecycle {
    replace_triggered_by = [google_certificate_manager_certificate.main]
  }
}

resource "google_certificate_manager_certificate_map_entry" "wildcard" {
  name         = "${var.prefix}-cert-map-entry-wildcard"
  map          = google_certificate_manager_certificate_map.main.name
  certificates = [google_certificate_manager_certificate.main.id]
  hostname     = "*.${var.domain_name}"
  project      = var.project_id
  labels       = local.all_labels
  lifecycle {
    replace_triggered_by = [google_certificate_manager_certificate.main]
  }
}
