terraform {
  # Capped at 1.5.7 because GCP Marketplace / Infra Manager runs no newer.
  required_version = ">= 1.5.7"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 6.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.17"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.36"
    }
    # null rather than the builtin terraform provider (terraform_data): GCP
    # Marketplace / Infra Manager permits a fixed provider set that excludes it.
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}
