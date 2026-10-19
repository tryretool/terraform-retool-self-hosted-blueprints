terraform {
  # >= 1.11 for write-only (value_wo) arguments.
  required_version = ">= 1.11"

  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
      # >= 4.21 for value_wo / value_wo_version on azurerm_key_vault_secret.
      # >= 5.0 for private_dns_zone_id on
      # azurerm_private_dns_zone_virtual_network_link, which replaced the
      # private_dns_zone_name + resource_group_name pair and has no v4 equivalent.
      version = ">= 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.0"
    }
  }
}
