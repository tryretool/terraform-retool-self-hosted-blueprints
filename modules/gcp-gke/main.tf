locals {
  cluster_name = "${var.prefix}-gke"
  location     = var.location != "" ? var.location : var.region
  all_labels   = merge(var.default_tags, var.tags)

  master_authorized_networks_config = length(var.master_authorized_networks) == 0 ? [] : [{
    cidr_blocks = var.master_authorized_networks
  }]
}

resource "google_project_service" "container" {
  project            = var.project_id
  service            = "container.googleapis.com"
  disable_on_destroy = false
}

# Node service account for GKE nodes. Granting cloud-platform scope + IAM roles is the
# GCP-recommended pattern (vs using default Compute SA which has broad permissions).
resource "google_service_account" "gke_nodes" {
  account_id   = substr("${var.prefix}-gke-nodes", 0, 30)
  display_name = "${var.prefix} GKE node service account"
  project      = var.project_id
}

# Minimum IAM roles required for GKE nodes to function.
resource "google_project_iam_member" "gke_nodes_log_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.gke_nodes.email}"
}

resource "google_project_iam_member" "gke_nodes_metric_writer" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.gke_nodes.email}"
}

resource "google_project_iam_member" "gke_nodes_monitoring_viewer" {
  project = var.project_id
  role    = "roles/monitoring.viewer"
  member  = "serviceAccount:${google_service_account.gke_nodes.email}"
}

resource "google_project_iam_member" "gke_nodes_artifact_reader" {
  project = var.project_id
  role    = "roles/artifactregistry.reader"
  member  = "serviceAccount:${google_service_account.gke_nodes.email}"
}

resource "google_container_cluster" "gke" {
  depends_on = [google_project_service.container]

  name    = local.cluster_name
  project = var.project_id

  # Regional location means masters are replicated across 3 zones automatically —
  # equivalent to how EKS always runs multi-AZ control plane. Use a zone here for
  # cheaper single-zone deployments.
  location = local.location

  network    = var.vpc.network_name
  subnetwork = var.vpc.subnet_name

  remove_default_node_pool = true
  initial_node_count       = 1

  deletion_protection = var.deletion_protection

  # VPC-native (alias IP) mode is required for Workload Identity and is the
  # recommended networking mode for all new GKE clusters.
  ip_allocation_policy {
    cluster_secondary_range_name  = var.vpc.pods_range_name
    services_secondary_range_name = var.vpc.services_range_name
  }

  # Workload Identity is the GCP equivalent of EKS IRSA / Pod Identity.
  # Pods can be mapped to GCP service accounts via k8s annotations.
  # The pool is always "{project_id}.svc.id.goog".
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  # Private nodes have no external IPs; Cloud NAT in the VPC module provides egress.
  # The master endpoint remains publicly accessible (same default as EKS
  # endpoint_public_access=true), but can be restricted via master_authorized_networks.
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
  }

  # cluster_version="" uses release_channel (idiomatic GKE).
  # cluster_version set → use min_master_version and omit release_channel.
  # The two are mutually exclusive in the Google provider.
  dynamic "release_channel" {
    for_each = var.cluster_version == "" ? [1] : []
    content {
      channel = var.release_channel
    }
  }

  min_master_version = var.cluster_version != "" ? var.cluster_version : null

  dynamic "master_authorized_networks_config" {
    for_each = local.master_authorized_networks_config
    content {
      dynamic "cidr_blocks" {
        for_each = master_authorized_networks_config.value.cidr_blocks
        content {
          cidr_block   = cidr_blocks.value.cidr_block
          display_name = cidr_blocks.value.display_name
        }
      }
    }
  }

  # Enable the GKE Gateway API controller. Required for the gke-l7-global-external-managed
  # GatewayClass used by the ingress module. CHANNEL_STANDARD tracks the stable Gateway
  # API release channel without pinning to a specific version.
  gateway_api_config {
    channel = "CHANNEL_STANDARD"
  }

  resource_labels = local.all_labels
}

resource "google_container_node_pool" "primary" {
  name     = "${var.prefix}-nodepool"
  project  = var.project_id
  location = local.location
  cluster  = google_container_cluster.gke.name

  # GKE cluster autoscaler scales this node pool automatically.
  # Unlike EKS+Karpenter, there is no separate controller pod — autoscaler
  # runs in the GKE control plane. min/max counts are per zone for regional clusters.
  autoscaling {
    min_node_count = var.node_min_count
    max_node_count = var.node_max_count
  }

  node_config {
    machine_type = var.node_machine_type
    disk_size_gb = var.node_disk_size_gb

    service_account = google_service_account.gke_nodes.email
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]

    # GKE_METADATA is required for Workload Identity to work on nodes.
    # This replaces the legacy node metadata (v1beta1) mode and exposes the
    # GKE metadata server to pods instead of the instance metadata endpoint.
    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    shielded_instance_config {
      enable_secure_boot = true
    }

    labels = local.all_labels
  }

  lifecycle {
    ignore_changes = [
      node_config[0].resource_labels
    ]
  }
}
