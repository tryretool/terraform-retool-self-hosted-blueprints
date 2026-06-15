terraform {
  # >= 1.11 for write-only (secret_data_wo) arguments.
  required_version = ">= 1.11"

  required_providers {
    google = {
      source = "hashicorp/google"
      # >= 6.16 for secret_data_wo / secret_data_wo_version on
      # google_secret_manager_secret_version.
      version = ">= 6.16"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.17"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.19"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}
