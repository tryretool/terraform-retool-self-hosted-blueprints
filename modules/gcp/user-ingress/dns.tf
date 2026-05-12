locals {
  all_labels = var.tags
}

resource "google_project_service" "compute" {
  project            = var.project_id
  service            = "compute.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "dns" {
  project            = var.project_id
  service            = "dns.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "certificatemanager" {
  project            = var.project_id
  service            = "certificatemanager.googleapis.com"
  disable_on_destroy = false
}

resource "google_dns_managed_zone" "main" {
  depends_on = [google_project_service.dns]

  name          = "${var.prefix}-zone"
  dns_name      = "${var.base_domain}."
  description   = "Managed zone for Retool deployment"
  project       = var.project_id
  labels        = local.all_labels
  force_destroy = true
}
