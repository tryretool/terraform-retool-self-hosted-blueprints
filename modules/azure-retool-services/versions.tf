terraform {
  # >= 1.11 for write-only (value_wo) arguments.
  required_version = ">= 1.11"

  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
      # >= 4.21 for value_wo / value_wo_version on azurerm_key_vault_secret;
      # >= 4.81 for user_assigned_identity_id on azurerm_federated_identity_credential.
      version = ">= 4.81"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.17"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.36"
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
