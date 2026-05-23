locals {
  outputs = {
    ingress_mode                = "azure-agic"
    agent_sandbox_proxy_enabled = var.enable_agent_sandbox_proxy
    ingress_class_name          = "azure-application-gateway"
    cluster_issuer_name         = var.enable_https ? "letsencrypt-prod" : null
    tls_secret_name             = var.enable_https ? "${var.prefix}-tls" : null
    agent_proxy_tls_secret_name = var.enable_https && var.enable_agent_sandbox_proxy ? "${var.prefix}-agent-proxy-tls" : null
    zone_name_servers           = azurerm_dns_zone.main.name_servers
    zone_dns_name               = azurerm_dns_zone.main.name
    public_ip_address           = azurerm_public_ip.appgw.ip_address
    appgw_name                  = azurerm_application_gateway.main.name
    agent_sandbox_proxy_url     = var.enable_agent_sandbox_proxy ? "${var.enable_https ? "https" : "http"}://agent-proxy.${var.domain_name}" : null
  }
}

output "ingress_mode" {
  description = "How Retool traffic reaches the cluster. \"azure-agic\" tells retool-helm to render the chart Ingress (and agent sandbox proxy Ingress) so the Application Gateway Ingress Controller reconciles them."
  value       = local.outputs.ingress_mode
}

output "agent_sandbox_proxy_enabled" {
  description = "Whether to provision an agent sandbox proxy Ingress on agent-proxy.<domain_name>."
  value       = local.outputs.agent_sandbox_proxy_enabled
}

output "ingress_class_name" {
  description = "ingressClassName to set on Retool's Ingress so AGIC reconciles it."
  value       = local.outputs.ingress_class_name
}

output "cluster_issuer_name" {
  description = "Name of the cert-manager ClusterIssuer that mints TLS certs for Retool ingresses, or null when HTTPS is disabled."
  value       = local.outputs.cluster_issuer_name
}

output "tls_secret_name" {
  description = "Name of the K8s TLS Secret holding the main Retool certificate, or null when HTTPS is disabled."
  value       = local.outputs.tls_secret_name
}

output "agent_proxy_tls_secret_name" {
  description = "Name of the K8s TLS Secret for the agent sandbox proxy ingress, or null when HTTPS / agent sandbox proxy is disabled."
  value       = local.outputs.agent_proxy_tls_secret_name
}

output "zone_name_servers" {
  description = "Name servers for the Azure DNS zone. Delegate these at your registrar."
  value       = local.outputs.zone_name_servers
}

output "zone_dns_name" {
  description = "Domain name for the Azure DNS zone."
  value       = local.outputs.zone_dns_name
}

output "public_ip_address" {
  description = "Static public IP address of the Application Gateway."
  value       = local.outputs.public_ip_address
}

output "appgw_name" {
  description = "Name of the Application Gateway resource."
  value       = local.outputs.appgw_name
}

output "agent_sandbox_proxy_url" {
  description = "Public URL for the agent sandbox proxy, or null when agent sandbox proxy is disabled."
  value       = local.outputs.agent_sandbox_proxy_url
}

output "outputs" {
  value       = local.outputs
  description = "Structured user-ingress outputs for composition with downstream modules."
}
