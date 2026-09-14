# The cluster and the resources that only exist alongside a cluster we create
# are now counted, so this module can adopt a pre-existing one instead
# (var.existing_cluster).

moved {
  from = google_container_cluster.gke
  to   = google_container_cluster.gke[0]
}

moved {
  from = google_container_node_pool.primary
  to   = google_container_node_pool.primary[0]
}

moved {
  from = google_project_service.container
  to   = google_project_service.container[0]
}

moved {
  from = google_service_account.gke_nodes
  to   = google_service_account.gke_nodes[0]
}

moved {
  from = google_project_iam_member.gke_nodes_log_writer
  to   = google_project_iam_member.gke_nodes_log_writer[0]
}

moved {
  from = google_project_iam_member.gke_nodes_metric_writer
  to   = google_project_iam_member.gke_nodes_metric_writer[0]
}

moved {
  from = google_project_iam_member.gke_nodes_monitoring_viewer
  to   = google_project_iam_member.gke_nodes_monitoring_viewer[0]
}

moved {
  from = google_project_iam_member.gke_nodes_artifact_reader
  to   = google_project_iam_member.gke_nodes_artifact_reader[0]
}
