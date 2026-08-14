output "alb_dns_name" {
  description = "DNS name of the new user-facing load balancer. Point domain_name at this to cut traffic over from the CloudFormation stack's load balancer."
  value       = module.user-ingress.alb_dns_name
}

output "hosted_zone_name_servers" {
  description = "Name servers of the Route53 zone this stack created for domain_name. Null when you brought your own certificate or manage DNS elsewhere, which is the usual case here."
  value       = module.user-ingress.zone_name_servers
}

output "cluster_name" {
  description = "EKS cluster name."
  value       = module.eks.outputs.name
}

output "kubeconfig_command" {
  description = "Command to configure kubectl against the new cluster."
  value       = "aws eks update-kubeconfig --profile ${var.aws_profile} --region ${var.region} --name ${module.eks.outputs.name}"
}

output "imported_databases" {
  description = "The databases now under Terraform's control, and the security groups whose rules are managed in imported-db-rules.tf."
  value = {
    retool = {
      identifier        = module.db-main.outputs.id
      address           = module.db-main.outputs.address
      security_group_id = module.db-main.security_group_id
    }
    temporal = var.temporal_db_mode == "imported" ? {
      identifier        = module.db-temporal[0].outputs.id
      address           = module.db-temporal[0].outputs.address
      security_group_id = module.db-temporal[0].security_group_id
    } : null
  }
}

output "modules" {
  description = "Structured outputs from every module in this stack."
  sensitive   = true # just to quiet the apply output
  value = {
    eks             = module.eks
    db-main         = module.db-main
    db-temporal     = module.db-temporal
    retool-services = module.retool-services
    user-ingress    = module.user-ingress
    retool          = module.retool
  }
}
