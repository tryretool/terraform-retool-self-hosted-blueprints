locals {
  outputs = {
    ingress_mode          = "external"
    zone_id               = aws_route53_zone.hosted_zone.zone_id
    zone_dns_name         = aws_route53_zone.hosted_zone.name
    zone_name             = aws_route53_zone.hosted_zone.name
    zone_name_servers     = aws_route53_zone.hosted_zone.name_servers
    acm_certificate_arn   = length(aws_acm_certificate.cert) > 0 ? aws_acm_certificate.cert[0].arn : null
    alb_id                = aws_lb.alb.id
    alb_dns_name          = aws_lb.alb.dns_name
    target_group_arn      = aws_lb_target_group.alb_target_group.arn
    alb_security_group_id = aws_security_group.alb.id
    https_listener_arn    = length(aws_lb_listener.https) > 0 ? aws_lb_listener.https[0].arn : null
  }
}

output "ingress_mode" {
  description = "How Retool traffic reaches the cluster. \"external\" means routing is handled outside the chart (here: an AWS Load Balancer Controller TargetGroupBinding CR provisioned by this module) and retool-helm renders no Ingress / HTTPRoute config."
  value       = local.outputs.ingress_mode
}

output "zone_id" {
  description = "Route53 hosted zone ID for the user domain"
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
  description = "Name servers of Route53 hosted zone to delegate the user domain to at the external registrar or DNS provider of parent domain"
  value       = local.outputs.zone_name_servers
}

output "acm_certificate_arn" {
  description = "ARN of the ACM certificate when HTTPS is enabled; otherwise null"
  value       = local.outputs.acm_certificate_arn
}

output "alb_id" {
  description = "ID of the application load balancer"
  value       = local.outputs.alb_id
}

output "alb_dns_name" {
  description = "DNS name of the application load balancer"
  value       = local.outputs.alb_dns_name
}

output "target_group_arn" {
  description = "ARN of the default target group for backend registration"
  value       = local.outputs.target_group_arn
}

output "alb_security_group_id" {
  description = "Security group attached to the ALB"
  value       = local.outputs.alb_security_group_id
}

output "https_listener_arn" {
  description = "ARN of the HTTPS listener when enable_https_listener is true; otherwise null"
  value       = local.outputs.https_listener_arn
}

output "outputs" {
  value       = local.outputs
  description = "Structured user-ingress outputs for composition with downstream modules."
}
