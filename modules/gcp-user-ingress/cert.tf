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

# R² app hostnames get their own DNS authorizations, certificate and map entries,
# so turning them on or off never replaces the main certificate. A wildcard
# certificate needs an authorization for the domain under the wildcard.
locals {
  apps_domain = "apps.${var.domain_name}"
  apps_cert_domains = var.enable_apps_domain ? {
    apps      = local.apps_domain
    sandboxes = "sandboxes.${local.apps_domain}"
  } : {}
}

resource "google_certificate_manager_dns_authorization" "apps" {
  for_each   = local.apps_cert_domains
  depends_on = [google_project_service.certificatemanager]

  name        = "${var.prefix}-${each.key}-cert-auth"
  description = "DNS authorization for the Retool *.${each.value} certificate"
  domain      = each.value
  project     = var.project_id
  labels      = local.all_labels
}

resource "google_dns_record_set" "apps_cert_validation" {
  for_each = local.apps_cert_domains

  name         = google_certificate_manager_dns_authorization.apps[each.key].dns_resource_record[0].name
  type         = google_certificate_manager_dns_authorization.apps[each.key].dns_resource_record[0].type
  ttl          = 60
  managed_zone = google_dns_managed_zone.main.name
  project      = var.project_id
  rrdatas      = [google_certificate_manager_dns_authorization.apps[each.key].dns_resource_record[0].data]
}

resource "google_certificate_manager_certificate" "apps" {
  count = var.enable_apps_domain ? 1 : 0

  name        = "${var.prefix}-apps-cert"
  description = "Google-managed certificate for Retool R² app and sandbox hostnames"
  project     = var.project_id
  labels      = local.all_labels

  managed {
    domains            = [for domain in values(local.apps_cert_domains) : "*.${domain}"]
    dns_authorizations = [for auth in values(google_certificate_manager_dns_authorization.apps) : auth.id]
  }
}

resource "google_certificate_manager_certificate_map_entry" "apps" {
  for_each = local.apps_cert_domains

  name         = "${var.prefix}-cert-map-entry-${each.key}"
  map          = google_certificate_manager_certificate_map.main.name
  certificates = [google_certificate_manager_certificate.apps[0].id]
  hostname     = "*.${each.value}"
  project      = var.project_id
  labels       = local.all_labels
  lifecycle {
    replace_triggered_by = [google_certificate_manager_certificate.apps]
  }
}
