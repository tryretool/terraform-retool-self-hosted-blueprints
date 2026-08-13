provider "google" {
  project = local.project_id
  region  = local.region
}

provider "google-beta" {
  project = local.project_id
  region  = local.region
}

# data.google_client_config.default.access_token is the GCP equivalent of
# "aws eks get-token". The google provider injects credentials directly into the
# access_token — no exec block is needed.
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
}

