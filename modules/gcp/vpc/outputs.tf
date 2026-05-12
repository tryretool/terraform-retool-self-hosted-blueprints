output "network_id" {
  description = "The ID of the VPC network"
  value       = module.vpc.network_id
}

output "network_name" {
  description = "The name of the VPC network (used by GKE and other resources)"
  value       = module.vpc.network_name
}

output "subnet_name" {
  description = "The name of the regional subnet"
  value       = module.vpc.subnets_names[0]
}

output "subnet_self_link" {
  description = "The self-link of the regional subnet (used by GKE)"
  value       = module.vpc.subnets_self_links[0]
}

output "pods_range_name" {
  description = "Name of the secondary IP range for GKE pods"
  value       = local.pods_range_name
}

output "services_range_name" {
  description = "Name of the secondary IP range for GKE services"
  value       = local.services_range_name
}
