locals {
  outputs = {
    static_ip_address          = google_compute_global_address.main.address
    zone_id                    = google_dns_managed_zone.main.id
    zone_dns_name              = google_dns_managed_zone.main.dns_name
    zone_name                  = google_dns_managed_zone.main.name
    zone_name_servers          = google_dns_managed_zone.main.name_servers
    cert_map_name              = google_certificate_manager_certificate_map.main.name
    gateway_name               = "retool"
    agent_sandbox_proxy_url    = var.enable_agent_sandbox_proxy ? "https://agent-proxy.${var.domain_name}" : null
  }
}

output "static_ip_address" {
  description = "Reserved static public IP address claimed by the Gateway. external-dns creates the A record pointing here once the Gateway HTTPRoute is programmed."
  value       = local.outputs.static_ip_address
}

output "zone_id" {
  description = "Cloud DNS managed zone ID."
  value       = local.outputs.zone_id
}

output "zone_dns_name" {
  description = "Domain name specified for the Cloud DNS zone."
  value       = local.outputs.zone_dns_name
}

output "zone_name" {
  description = "Name specified for the Cloud DNS zone."
  value       = local.outputs.zone_name
}

output "zone_name_servers" {
  description = "Name servers for the Cloud DNS zone. Delegate these at your registrar so the domain resolves correctly and Certificate Manager DNS authorization can validate."
  value       = local.outputs.zone_name_servers
}

output "cert_map_name" {
  description = "Certificate Manager certificate map name attached to the Gateway."
  value       = local.outputs.cert_map_name
}

output "gateway_name" {
  description = "Name of the K8s Gateway resource. Use this in the retool-helm httpRoute.parentRefs[].name value."
  value       = local.outputs.gateway_name
}

output "agent_sandbox_proxy_url" {
  description = "Public URL for the agent sandbox proxy, or null when agent sandbox proxy is disabled."
  value       = local.outputs.agent_sandbox_proxy_url
}

output "outputs" {
  value       = local.outputs
  description = "Structured user-ingress outputs for composition with downstream modules."
}
