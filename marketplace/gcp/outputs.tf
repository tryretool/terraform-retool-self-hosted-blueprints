output "zone_name_servers" {
  description = "Delegate domain_name to these Cloud DNS name servers."
  value       = module.user-ingress.zone_name_servers
}

output "static_ip_address" {
  description = "Reserved Gateway IP. external-dns creates the A record once the HTTPRoute is programmed."
  value       = module.user-ingress.static_ip_address
}
