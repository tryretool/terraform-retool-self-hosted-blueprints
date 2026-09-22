## `aws-user-ingress` module

This is a Terraform module which provides the recommended user-facing (ingress) networking stack for production Retool deployments.

* Creates a Route53 hosted DNS zone at the given domain name (`var.domain_name`)
* Creates an ACM cert for `${var.domain_name}` and `*.${var.domain_name}` (wildcard)
  * Installs DNS validation records into above Route53 zone
* Creates an ALB instance with preconfigured listeners, routing rules, backends and health checks for serving Retool traffic

### Bringing your own certificate and DNS

The zone and certificate above are the defaults, not a requirement. If TLS
certificates and DNS for your domain are managed centrally (a common constraint
when migrating an existing deployment), you can opt out of both:

* `acm_certificate_arn` — attach an existing certificate to the HTTPS listener.
  No certificate and no ACM validation records are created.
* `create_hosted_zone = false` — do not create a Route53 zone. Set
  `hosted_zone_id` to have the module still write the ALB alias records into an
  existing zone, or leave it `null` to manage no DNS at all and point your
  domain at the `alb_dns_name` output yourself.

When no zone is created, the `zone_dns_name` / `zone_name` / `zone_name_servers`
outputs are `null`, and `zone_id` reflects `hosted_zone_id` (also possibly `null`).

### Edge authentication (OIDC)

Set `alb_authenticate_oidc` to make the HTTPS listener authenticate users against
an OIDC identity provider *before* forwarding to Retool, using an ordered
`authenticate-oidc` → `forward` default action. This is authentication at the
load balancer, in front of the application, and is independent of Retool's own
SSO configuration.

> [!NOTE] This module is intended to be used in conjunction with the other AWS-specific modules in [`retool-self-hosted-blueprints`](https://github.com/tryretool/retool-self-hosted-blueprints). See the [usage examples](https://github.com/tryretool/retool-self-hosted-blueprints/tree/main/examples) for references on how to use this module.
