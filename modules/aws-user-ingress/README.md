## `aws-user-ingress` module

This is a Terraform module which provides the recommended user-facing (ingress) networking stack for production Retool deployments.

* Creates a Route53 hosted DNS zone at the given domain name (`var.domain_name`)
* Creates an ACM cert for `${var.domain_name}` and `*.${var.domain_name}` (wildcard)
  * Installs DNS validation records into above Route53 zone
* Creates an ALB instance with preconfigured listeners, routing rules, backends and health checks for serving Retool traffic

> [!NOTE] This module is intended to be used in conjunction with the other AWS-specific modules in [`retool-self-hosted-blueprints`](https://github.com/tryretool/retool-self-hosted-blueprints). See the [usage examples](https://github.com/tryretool/retool-self-hosted-blueprints/tree/main/examples) for references on how to use this module.
