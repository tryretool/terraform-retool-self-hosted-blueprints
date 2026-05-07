output "zone_id" {
  description = "Route53 hosted zone ID for the user domain"
  value       = aws_route53_zone.hosted_zone.zone_id
}

output "zone_dns_name" {
  description = "Domain name specified for the Cloud DNS zone."
  value       = aws_route53_zone.hosted_zone.name
}

output "zone_name" {
  description = "Name specified for the Cloud DNS zone."
  value       = aws_route53_zone.hosted_zone.name
}

output "zone_name_servers" {
  description = "Name servers of Route53 hosted zone to delegate the user domain to at the external registrar or DNS provider of parent domain"
  value       = aws_route53_zone.hosted_zone.name_servers
}

output "acm_certificate_arn" {
  description = "ARN of the ACM certificate when HTTPS is enabled; otherwise null"
  value       = length(aws_acm_certificate.cert) > 0 ? aws_acm_certificate.cert[0].arn : null
}

output "alb_id" {
  description = "ID of the application load balancer"
  value       = aws_lb.alb.id
}

output "alb_dns_name" {
  description = "DNS name of the application load balancer"
  value       = aws_lb.alb.dns_name
}

output "target_group_arn" {
  description = "ARN of the default target group for backend registration"
  value       = aws_lb_target_group.alb_target_group.arn
}

output "alb_security_group_id" {
  description = "Security group attached to the ALB"
  value       = aws_security_group.alb.id
}

output "https_listener_arn" {
  description = "ARN of the HTTPS listener when enable_https_listener is true; otherwise null"
  value       = length(aws_lb_listener.https) > 0 ? aws_lb_listener.https[0].arn : null
}

output "agent_sandbox_proxy_url" {
  description = "Public URL for the agent sandbox proxy (WebSocket endpoint for browsers), or null when disabled."
  value       = var.enable_agent_sandbox_proxy ? "${var.enable_https_listener ? "https" : "http"}://agent-proxy.${var.domain_name}" : null
}
