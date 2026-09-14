# ---------- Azure DNS Zone ----------

resource "azurerm_dns_zone" "main" {
  name                = var.domain_name
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

# A records pointing to the AppGW static public IP.
# Unlike AGC (which only exposes an FQDN), the AppGW has a real static IP
# so standard A records work at both the apex and wildcard.
#
# Only created when this module manages the Application Gateway. With AGIC
# disabled (BYO ingress in a shared cluster), point your own A records at your
# ingress controller's address.

resource "azurerm_dns_a_record" "main" {
  count = var.enable_agic ? 1 : 0

  name                = "@"
  zone_name           = azurerm_dns_zone.main.name
  resource_group_name = var.resource_group_name
  ttl                 = 300
  target_resource_id  = azurerm_public_ip.appgw[0].id
}

resource "azurerm_dns_a_record" "wildcard" {
  count = var.enable_agic ? 1 : 0

  name                = "*"
  zone_name           = azurerm_dns_zone.main.name
  resource_group_name = var.resource_group_name
  ttl                 = 300
  target_resource_id  = azurerm_public_ip.appgw[0].id
}
