data "google_client_config" "default" {}

provider "kubernetes" {
  host                   = "https://${module.gke.cluster.endpoint}"
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(module.gke.cluster.certificate_authority_data)
}

provider "helm" {
  kubernetes {
    host                   = "https://${module.gke.cluster.endpoint}"
    token                  = data.google_client_config.default.access_token
    cluster_ca_certificate = base64decode(module.gke.cluster.certificate_authority_data)
  }

  # Helm does not use Application Default Credentials for OCI. Without this the
  # chart pull is anonymous and Artifact Registry returns 403.
  registry {
    url      = "oci://us-docker.pkg.dev"
    username = "oauth2accesstoken"
    password = data.google_client_config.default.access_token
  }
}
