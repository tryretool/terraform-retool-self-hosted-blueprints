terraform {
  # >= 1.3 for optional() object attributes with defaults.
  required_version = ">= 1.3"

  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
      # >= 4.81 for user_assigned_identity_id on azurerm_federated_identity_credential.
      version = ">= 4.81"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.17"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.19"
    }
  }
}
