terraform {
  # >= 1.3 for optional() object attributes with defaults. Deliberately not
  # raised further: this module is cloud-agnostic and is deployed on GCP via
  # Marketplace / Infra Manager, which runs no newer than 1.5.7.
  required_version = ">= 1.3"

  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.17"
    }
  }
}
