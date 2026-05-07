locals {
  name_slug = replace(var.domain_name, ".", "-")

  # Application load balancer names: max 32 characters; alphanumeric and hyphens only.
  alb_name = length(local.name_slug) <= 23 ? "${local.name_slug}-ingress" : "${substr(local.name_slug, 0, 23)}-ingress"

  # Target group name: max 32 characters; alphanumeric and hyphens only.
  tg_name = length(local.name_slug) <= 27 ? "${local.name_slug}-tg" : "${substr(local.name_slug, 0, 27)}-tg"

  ae_proxy_tg_name = length(local.name_slug) <= 24 ? "${local.name_slug}-ae-tg" : "${substr(local.name_slug, 0, 24)}-ae-tg"
}

resource "aws_route53_zone" "hosted_zone" {
  name = var.domain_name
}

# ACM only provisions DNS-validated public certs for domains ACM can resolve
# publicly. Names under reserved suffixes (e.g. *.invalid) never validate, and
# the AWS provider waits until ISSUED — so we only create the certificate when
# enable_https_listener is true (real customer domains with delegatable DNS).
resource "aws_acm_certificate" "cert" {
  count = var.enable_https_listener ? 1 : 0

  domain_name = var.domain_name
  subject_alternative_names = [
    "*.${var.domain_name}"
  ]

  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "cert_validation" {
  for_each = var.enable_https_listener ? {
    for dvo in aws_acm_certificate.cert[0].domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      type   = dvo.resource_record_type
      record = dvo.resource_record_value
    }
  } : {}

  allow_overwrite = true

  zone_id = aws_route53_zone.hosted_zone.zone_id
  name    = each.value.name
  type    = each.value.type
  ttl     = 60
  records = [each.value.record]
}

resource "aws_acm_certificate_validation" "cert_valid_status" {
  count           = var.enable_https_listener ? 1 : 0
  certificate_arn = aws_acm_certificate.cert[0].arn
}

resource "aws_security_group" "alb" {
  name        = "${replace(var.domain_name, ".", "-")}-alb"
  description = "Ingress for user-facing application load balancer"
  vpc_id      = var.vpc.vpc_id

  ingress {
    description = "HTTPS from internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_vpc_security_group_ingress_rule" "retool_from_alb" {
  security_group_id            = var.eks.node_security_group_id
  description                  = "Retool HTTP from user-managed ALB"
  referenced_security_group_id = aws_security_group.alb.id
  ip_protocol                  = "tcp"
  from_port                    = var.retool_service_port
  to_port                      = var.retool_service_port
}

resource "aws_lb" "alb" {
  name               = local.alb_name
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = var.vpc.public_subnet_ids
}

resource "aws_lb_target_group" "alb_target_group" {
  name        = local.tg_name
  port        = var.retool_service_port
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = var.vpc.vpc_id

  health_check {
    enabled             = true
    path                = "/api/checkHealth"
    port                = "traffic-port"
    protocol            = "HTTP"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    matcher             = "200"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb_listener" "https" {
  count = var.enable_https_listener ? 1 : 0

  load_balancer_arn = aws_lb.alb.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate.cert[0].arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.alb_target_group.arn
  }

  depends_on = [aws_acm_certificate_validation.cert_valid_status[0]]
}

resource "aws_lb_listener" "http_redirect" {
  count = var.enable_https_listener ? 1 : 0

  load_balancer_arn = aws_lb.alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

# Until the ACM certificate is ISSUED (public NS delegation), ALB rejects HTTPS
# listeners. Use this forward listener when enable_https_listener is false.
resource "aws_lb_listener" "http_forward" {
  count = var.enable_https_listener ? 0 : 1

  load_balancer_arn = aws_lb.alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.alb_target_group.arn
  }
}

resource "kubectl_manifest" "target_group_binding" {
  yaml_body = yamlencode({
    apiVersion = "elbv2.k8s.aws/v1beta1"
    kind       = "TargetGroupBinding"
    metadata = {
      name      = local.tg_name
      namespace = var.retool_service_namespace
    }
    spec = {
      targetGroupARN = aws_lb_target_group.alb_target_group.arn
      targetType     = "ip"
      serviceRef = {
        name = var.retool_service_name
        port = var.retool_service_port
      }
    }
  })

  lifecycle {
    replace_triggered_by = [
      aws_lb_target_group.alb_target_group,
    ]
  }
}

resource "aws_route53_record" "alb_alias" {
  zone_id = aws_route53_zone.hosted_zone.zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_lb.alb.dns_name
    zone_id                = aws_lb.alb.zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "alb_alias_wildcard" {
  zone_id = aws_route53_zone.hosted_zone.zone_id
  name    = "*.${var.domain_name}"
  type    = "A"

  alias {
    name                   = aws_lb.alb.dns_name
    zone_id                = aws_lb.alb.zone_id
    evaluate_target_health = true
  }
}

# --- Agent Sandbox Proxy (gated on enable_agent_sandbox_proxy) ---

resource "aws_vpc_security_group_ingress_rule" "ae_proxy_from_alb" {
  count = var.enable_agent_sandbox_proxy ? 1 : 0

  security_group_id            = var.eks.node_security_group_id
  description                  = "Agent sandbox proxy from user-managed ALB"
  referenced_security_group_id = aws_security_group.alb.id
  ip_protocol                  = "tcp"
  from_port                    = var.agent_sandbox_proxy_port
  to_port                      = var.agent_sandbox_proxy_port
}

resource "aws_lb_target_group" "agent_sandbox_proxy" {
  count = var.enable_agent_sandbox_proxy ? 1 : 0

  name        = local.ae_proxy_tg_name
  port        = var.agent_sandbox_proxy_port
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = var.vpc.vpc_id

  health_check {
    enabled             = true
    path                = "/"
    port                = "traffic-port"
    protocol            = "HTTP"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    matcher             = "200-404"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb_listener_rule" "agent_sandbox_proxy_https" {
  count = var.enable_agent_sandbox_proxy && var.enable_https_listener ? 1 : 0

  listener_arn = aws_lb_listener.https[0].arn

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.agent_sandbox_proxy[0].arn
  }

  condition {
    host_header {
      values = ["agent-proxy.${var.domain_name}"]
    }
  }
}

resource "aws_lb_listener_rule" "agent_sandbox_proxy_http" {
  count = var.enable_agent_sandbox_proxy && !var.enable_https_listener ? 1 : 0

  listener_arn = aws_lb_listener.http_forward[0].arn

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.agent_sandbox_proxy[0].arn
  }

  condition {
    host_header {
      values = ["agent-proxy.${var.domain_name}"]
    }
  }
}

resource "kubectl_manifest" "agent_sandbox_proxy_tgb" {
  count = var.enable_agent_sandbox_proxy ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "elbv2.k8s.aws/v1beta1"
    kind       = "TargetGroupBinding"
    metadata = {
      name      = local.ae_proxy_tg_name
      namespace = var.retool_service_namespace
    }
    spec = {
      targetGroupARN = aws_lb_target_group.agent_sandbox_proxy[0].arn
      targetType     = "ip"
      serviceRef = {
        name = var.agent_sandbox_proxy_service_name
        port = var.agent_sandbox_proxy_port
      }
    }
  })

  lifecycle {
    replace_triggered_by = [
      aws_lb_target_group.agent_sandbox_proxy,
    ]
  }
}
