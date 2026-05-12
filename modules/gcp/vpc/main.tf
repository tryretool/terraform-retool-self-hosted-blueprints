locals {
  pods_range_name     = "${var.prefix}-pods"
  services_range_name = "${var.prefix}-services"

  psa_address       = split("/", var.private_service_access_ip_range)[0]
  psa_prefix_length = tonumber(split("/", var.private_service_access_ip_range)[1])
}

resource "google_project_service" "compute" {
  project            = var.project_id
  service            = "compute.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "servicenetworking" {
  project            = var.project_id
  service            = "servicenetworking.googleapis.com"
  disable_on_destroy = false
}

# GCP VPCs are global resources — one network spans all regions. The subnets
# within it are regional. This differs from AWS where VPCs are regional.
module "vpc" {
  source  = "terraform-google-modules/network/google"
  version = "11.0.0"

  depends_on = [google_project_service.compute]

  project_id   = var.project_id
  network_name = "${var.prefix}-network"

  subnets = [
    {
      subnet_name           = "${var.prefix}-subnet"
      subnet_ip             = var.subnet_ip_range
      subnet_region         = var.region
      subnet_private_access = true
    }
  ]

  # Secondary ranges are required for VPC-native (alias IP) GKE clusters.
  # VPC-native mode is required for Workload Identity.
  secondary_ranges = {
    "${var.prefix}-subnet" = [
      {
        range_name    = local.pods_range_name
        ip_cidr_range = var.pods_ip_range
      },
      {
        range_name    = local.services_range_name
        ip_cidr_range = var.services_ip_range
      }
    ]
  }
}

# Reserves a range and creates a VPC peering connection to servicenetworking.googleapis.com.
# This is required before any Cloud SQL instance with private IP can be created in this VPC.
# The database module must depend_on this module to ensure ordering.
module "private_service_access" {
  source  = "terraform-google-modules/sql-db/google//modules/private_service_access"
  version = "25.2.2"

  depends_on = [module.vpc, google_project_service.servicenetworking]

  project_id    = var.project_id
  vpc_network   = module.vpc.network_name
  address       = local.psa_address
  ip_version    = "IPV4"
  prefix_length = local.psa_prefix_length
  # A CloudSQL db created using this PSA connection will stay alive in the
  # background for 7d after deletion, during which time it will block deletion
  # of the PSA itself. Setting deletion_policy to abandon unblocks stack destroy
  # in that scenario. 
  deletion_policy = "ABANDON"
}

# Cloud Router is required by Cloud NAT.
resource "google_compute_router" "router" {
  name    = "${var.prefix}-router"
  project = var.project_id
  region  = var.region
  network = module.vpc.network_id
}

# Cloud NAT provides outbound internet access for private GKE nodes (nodes with no
# external IP). This replaces per-AZ NAT Gateways in AWS — Cloud NAT is a managed
# regional service, so no per-zone cost or configuration is needed.
resource "google_compute_router_nat" "nat" {
  name    = "${var.prefix}-nat"
  project = var.project_id
  region  = var.region
  router  = google_compute_router.router.name

  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}
