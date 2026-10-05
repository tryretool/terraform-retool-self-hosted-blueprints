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

### Internal (private) ingress

By default the module builds an internet-facing ALB in `vpc.public_subnet_ids`.
Set `alb_internal = true` to build an **internal** ALB in
`vpc.private_subnet_ids` instead:

```hcl
module "user-ingress" {
  # ...
  vpc          = module.vpc.outputs
  alb_internal = true
}
```

`module.vpc.outputs` already carries `private_subnet_ids`, so no other wiring
changes. `alb_internal` is a create-time attribute on the load balancer:
flipping an existing deployment from public to internal **replaces the ALB** and
yields a new `alb_dns_name`, so treat it as a cutover rather than an in-place
update.

### Restricting inbound access (allowlist)

Use `alb_ingress_cidr_blocks` (and `alb_ingress_ipv6_cidr_blocks`) to restrict
the ports 443/80 security-group rules to approved networks instead of the
internet:

```hcl
module "user-ingress" {
  # ...
  alb_internal            = true
  alb_ingress_cidr_blocks = ["10.0.0.0/8", "172.20.0.0/16", "192.168.0.0/16"]
}
```

When `alb_ingress_cidr_blocks` is left `null`, the module defaults to the VPC
CIDR (`vpc.vpc_cidr_block`) for internal ALBs, and to `["0.0.0.0/0"]` for
internet-facing ALBs. For an internal ALB that means it is reachable from the
whole VPC unless you set the list explicitly, so set your corporate, VPN, and
connected-AWS-network CIDRs.

### Private DNS

Two options are supported for keeping `domain_name` on private/internal DNS:

* **Let this module create a private zone.** Set `create_hosted_zone = true`
  and `private_hosted_zone = true`. The zone is created private and associated
  with the module's VPC.
* **Use a corporate-managed (or otherwise existing) private zone.** Set
  `create_hosted_zone = false` and pass its ID as `hosted_zone_id`. The module
  writes the ALB alias records into it but creates no zone.
  Leave `hosted_zone_id = null` to create no DNS records at all and point
  `domain_name` at `alb_dns_name` yourself.

A private hosted zone cannot satisfy a public ACM DNS validation, so
`private_hosted_zone = true` cannot be combined with a certificate minted by
this module. Bring your own certificate with `acm_certificate_arn` (or disable
HTTPS).

A zone created here is associated with the module's VPC only. Reaching it from
peered/transit-gateway VPCs or an on-premises network requires DNS forwarding,
or a zone managed centrally and supplied via `hosted_zone_id`.

### Edge authentication (OIDC)

Set `alb_authenticate_oidc` to make the HTTPS listener authenticate users against
an OIDC identity provider *before* forwarding to Retool, using an ordered
`authenticate-oidc` → `forward` default action. This is authentication at the
load balancer, in front of the application, and is independent of Retool's own
SSO configuration.

> [!NOTE] This module is intended to be used in conjunction with the other AWS-specific modules in [`retool-self-hosted-blueprints`](https://github.com/tryretool/retool-self-hosted-blueprints). See the [usage examples](https://github.com/tryretool/retool-self-hosted-blueprints/tree/main/examples) for references on how to use this module.
