locals {
  outputs = {
    ingress_mode        = "azure-agic"
    ingress_class_name  = var.ingress_class_name
    cluster_issuer_name = var.enable_https ? local.cluster_issuer_name : null
    tls_secret_name     = var.enable_https ? "${var.prefix}-tls" : null
    zone_name_servers   = azurerm_dns_zone.main.name_servers
    zone_dns_name       = azurerm_dns_zone.main.name
    public_ip_address   = var.enable_agic ? azurerm_public_ip.appgw[0].ip_address : null
    appgw_name          = var.enable_agic ? azurerm_application_gateway.main[0].name : null
  }
}

output "ingress_mode" {
  description = "How Retool traffic reaches the cluster. \"azure-agic\" tells retool-helm to render the chart Ingress so the Application Gateway Ingress Controller reconciles it."
  value       = local.outputs.ingress_mode
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

output "outputs" {
  value       = local.outputs
  description = "Structured user-ingress outputs for composition with downstream modules."
}
