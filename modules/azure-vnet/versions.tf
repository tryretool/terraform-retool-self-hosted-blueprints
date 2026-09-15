terraform {
  required_version = ">= 1.0"

  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
      # >= 4.81 for rbac_authorization_enabled on azurerm_key_vault, which
      # replaced enable_rbac_authorization and is required as of azurerm 5.0.
      version = ">= 4.81"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.0"
    }
  }
}
