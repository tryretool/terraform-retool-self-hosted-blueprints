# ---------- Azure DNS Zone ----------

resource "azurerm_dns_zone" "main" {
  name                = var.domain_name
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

# A records pointing to the AppGW static public IP.
# Unlike AGC (which only exposes an FQDN), the AppGW has a real static IP
# so standard A records work at both the apex and wildcard.

resource "azurerm_dns_a_record" "main" {
  name                = "@"
  zone_name           = azurerm_dns_zone.main.name
  resource_group_name = var.resource_group_name
  ttl                 = 300
  target_resource_id  = azurerm_public_ip.appgw.id
}

resource "azurerm_dns_a_record" "wildcard" {
  name                = "*"
  zone_name           = azurerm_dns_zone.main.name
  resource_group_name = var.resource_group_name
  ttl                 = 300
  target_resource_id  = azurerm_public_ip.appgw.id
}
