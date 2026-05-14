output "zone_name_servers" {
  description = "Name servers for the Azure DNS zone. Delegate these at your registrar."
  value       = azurerm_dns_zone.main.name_servers
}

output "zone_dns_name" {
  description = "Domain name for the Azure DNS zone."
  value       = azurerm_dns_zone.main.name
}

output "public_ip_address" {
  description = "Static public IP address of the Application Gateway."
  value       = azurerm_public_ip.appgw.ip_address
}

output "appgw_name" {
  description = "Name of the Application Gateway resource."
  value       = azurerm_application_gateway.main.name
}

output "agent_sandbox_proxy_url" {
  description = "Public URL for the agent sandbox proxy, or null when agent sandbox proxy is disabled."
  value       = var.enable_agent_sandbox_proxy ? "${var.enable_https ? "https" : "http"}://agent-proxy.${var.domain_name}" : null
}
