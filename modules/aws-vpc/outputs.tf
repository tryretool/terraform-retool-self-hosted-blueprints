locals {
  outputs = {
    vpc_id = module.vpc.vpc_id
    vpc_cidr_block = module.vpc.vpc_cidr_block
    private_subnet_ids = module.vpc.private_subnets
    public_subnet_ids = module.vpc.public_subnets
  }
}

output "vpc_id" {
  value       = local.outputs.vpc_id
  description = "VPC id"
}

output "vpc_cidr_block" {
  value       = local.outputs.vpc_cidr_block
  description = "The CIDR block of the VPC"
}

output "private_subnet_ids" {
  value       = local.outputs.private_subnet_ids
  description = "List of IDs of private subnets"
}

output "public_subnet_ids" {
  value       = local.outputs.public_subnet_ids
  description = "List of IDs of public subnets"
}

output "outputs" {
  value = local.outputs
  description = "Structured VPC outputs for composition with downstream modules."
}
