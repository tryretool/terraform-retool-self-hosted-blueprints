output "static_ip_address" {
  description = "Reserved static public IP address claimed by the Gateway. external-dns creates the A record pointing here once the Gateway HTTPRoute is programmed."
  value       = google_compute_global_address.main.address
}

output "zone_id" {
  description = "Cloud DNS managed zone ID."
  value       = google_dns_managed_zone.main.id
}

output "zone_dns_name" {
  description = "Domain name specified for the Cloud DNS zone."
  value       = google_dns_managed_zone.main.dns_name
}

output "zone_name" {
  description = "Name specified for the Cloud DNS zone."
  value       = google_dns_managed_zone.main.name
}

output "zone_name_servers" {
  description = "Name servers for the Cloud DNS zone. Delegate these at your registrar so the domain resolves correctly and Certificate Manager DNS authorization can validate."
  value       = google_dns_managed_zone.main.name_servers
}

output "cert_map_name" {
  description = "Certificate Manager certificate map name attached to the Gateway."
  value       = google_certificate_manager_certificate_map.main.name
}

output "gateway_name" {
  description = "Name of the K8s Gateway resource. Use this in the retool-helm httpRoute.parentRefs[].name value."
  value       = "retool"
}
