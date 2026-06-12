terraform {
  # >= 1.11 for write-only (value_wo) arguments.
  required_version = ">= 1.11"

  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
      # >= 4.21 for value_wo / value_wo_version on azurerm_key_vault_secret.
      version = ">= 4.21"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.0"
    }
  }
}
