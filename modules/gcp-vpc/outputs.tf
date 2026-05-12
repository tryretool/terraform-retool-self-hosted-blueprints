locals {
  outputs = {
    network_id          = module.vpc.network_id
    network_name        = module.vpc.network_name
    subnet_name         = module.vpc.subnets_names[0]
    subnet_self_link    = module.vpc.subnets_self_links[0]
    pods_range_name     = local.pods_range_name
    services_range_name = local.services_range_name
  }
}

output "network_id" {
  description = "The ID of the VPC network"
  value       = local.outputs.network_id
}

output "network_name" {
  description = "The name of the VPC network (used by GKE and other resources)"
  value       = local.outputs.network_name
}

output "subnet_name" {
  description = "The name of the regional subnet"
  value       = local.outputs.subnet_name
}

output "subnet_self_link" {
  description = "The self-link of the regional subnet (used by GKE)"
  value       = local.outputs.subnet_self_link
}

output "pods_range_name" {
  description = "Name of the secondary IP range for GKE pods"
  value       = local.outputs.pods_range_name
}

output "services_range_name" {
  description = "Name of the secondary IP range for GKE services"
  value       = local.outputs.services_range_name
}

output "outputs" {
  value       = local.outputs
  description = "Structured VPC outputs for composition with downstream modules."
}
