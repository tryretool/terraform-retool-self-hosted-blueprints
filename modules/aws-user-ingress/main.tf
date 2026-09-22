locals {
  # Namespace of the Retool Service the TargetGroupBinding registers, sourced
  # from the retool-services outputs (falls back to "default").
  retool_service_namespace = coalesce(try(var.retool_services.retool_namespace, null), "default")

  name_slug = replace(var.domain_name, ".", "-")

  # Application load balancer names: max 32 characters; alphanumeric and hyphens only.
  alb_name = length(local.name_slug) <= 23 ? "${local.name_slug}-ingress" : "${substr(local.name_slug, 0, 23)}-ingress"

  # Target group name: max 32 characters; alphanumeric and hyphens only.
  tg_name = length(local.name_slug) <= 27 ? "${local.name_slug}-tg" : "${substr(local.name_slug, 0, 27)}-tg"

  # Whether this module manages DNS at all. Must be decidable from configuration
  # alone: it gates resource counts, and the id of a zone we are about to create
  # is not known until apply.
  manage_dns = var.create_hosted_zone || var.hosted_zone_id != null

  # The zone this module writes records into: the one it created, or an existing
  # one the caller nominated. Null means DNS is managed entirely outside this
  # stack and we write no records at all.
  zone_id = var.create_hosted_zone ? aws_route53_zone.hosted_zone[0].zone_id : var.hosted_zone_id

  # Only mint a certificate when HTTPS is on and the caller didn't bring one.
  create_certificate = var.enable_https_listener && var.acm_certificate_arn == null

  # The certificate the HTTPS listener serves — brought in or minted here. Null
  # when there is no HTTPS listener to attach it to.
  certificate_arn = (
    var.enable_https_listener
    ? coalesce(var.acm_certificate_arn, one(aws_acm_certificate.cert[*].arn))
    : null
  )
}

resource "aws_route53_zone" "hosted_zone" {
  count = var.create_hosted_zone ? 1 : 0

  name = var.domain_name
}

# The hosted zone and the ALB alias records below became conditional in v0.4.
# These keep existing deployments from planning a destroy/create when their
# state still records the resources at their pre-count addresses.
moved {
  from = aws_route53_zone.hosted_zone
  to   = aws_route53_zone.hosted_zone[0]
}

moved {
  from = aws_route53_record.alb_alias
  to   = aws_route53_record.alb_alias[0]
}

moved {
  from = aws_route53_record.alb_alias_wildcard
  to   = aws_route53_record.alb_alias_wildcard[0]
}

# ACM only provisions DNS-validated public certs for domains ACM can resolve
# publicly. Names under reserved suffixes (e.g. *.invalid) never validate, and
# the AWS provider waits until ISSUED — so we only create the certificate when
# enable_https_listener is true (real customer domains with delegatable DNS).
resource "aws_acm_certificate" "cert" {
  count = local.create_certificate ? 1 : 0

  domain_name = var.domain_name
  subject_alternative_names = [
    "*.${var.domain_name}"
  ]

  validation_method = "DNS"

  lifecycle {
    precondition {
      condition     = local.manage_dns
      error_message = "aws-user-ingress cannot validate a certificate for ${var.domain_name} without a hosted zone. Either leave create_hosted_zone = true, set hosted_zone_id to an existing zone, or supply acm_certificate_arn to bring your own certificate."
    }
  }
}

resource "aws_route53_record" "cert_validation" {
  for_each = local.create_certificate ? {
    for dvo in aws_acm_certificate.cert[0].domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      type   = dvo.resource_record_type
      record = dvo.resource_record_value
    }
  } : {}

  allow_overwrite = true

  zone_id = local.zone_id
  name    = each.value.name
  type    = each.value.type
  ttl     = 60
  records = [each.value.record]
}

resource "aws_acm_certificate_validation" "cert_valid_status" {
  count           = local.create_certificate ? 1 : 0
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
}

resource "aws_lb_listener" "https" {
  count = var.enable_https_listener ? 1 : 0

  load_balancer_arn = aws_lb.alb.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = local.certificate_arn

  # Edge authentication, when configured: users must complete the OIDC flow
  # before any request reaches Retool. `order` matters — ALB evaluates actions in
  # ascending order and the authenticate action has to run first.
  dynamic "default_action" {
    for_each = var.alb_authenticate_oidc != null ? [var.alb_authenticate_oidc] : []

    content {
      type  = "authenticate-oidc"
      order = 1

      authenticate_oidc {
        issuer                              = default_action.value.issuer
        authorization_endpoint              = default_action.value.authorization_endpoint
        token_endpoint                      = default_action.value.token_endpoint
        user_info_endpoint                  = default_action.value.user_info_endpoint
        client_id                           = default_action.value.client_id
        client_secret                       = default_action.value.client_secret
        scope                               = default_action.value.scope
        session_cookie_name                 = default_action.value.session_cookie_name
        session_timeout                     = default_action.value.session_timeout
        on_unauthenticated_request          = default_action.value.on_unauthenticated_request
        authentication_request_extra_params = default_action.value.authentication_request_extra_params
      }
    }
  }

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.alb_target_group.arn
    order            = var.alb_authenticate_oidc != null ? 2 : null
  }

  depends_on = [aws_acm_certificate_validation.cert_valid_status]
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
      namespace = local.retool_service_namespace
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
  count = local.manage_dns ? 1 : 0

  zone_id = local.zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_lb.alb.dns_name
    zone_id                = aws_lb.alb.zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "alb_alias_wildcard" {
  count = local.manage_dns ? 1 : 0

  zone_id = local.zone_id
  name    = "*.${var.domain_name}"
  type    = "A"

  alias {
    name                   = aws_lb.alb.dns_name
    zone_id                = aws_lb.alb.zone_id
    evaluate_target_health = true
  }
}
