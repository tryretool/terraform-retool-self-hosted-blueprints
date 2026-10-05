# Internal-only ingress (private ALB + CIDR allowlist)

> [!WARNING]
> This guide currently covers AWS (`aws-user-ingress`) only. Private
> ingress support for the GCP and Azure user-ingress modules is not yet
> available.

This guide covers running the AWS `aws-user-ingress` module in an **internal**
configuration: an internal (private) Application Load Balancer in the VPC's
private subnets, inbound access restricted to approved corporate, VPN, and
connected AWS network CIDRs, and DNS kept private. Running private-only ingress
is fully supported but only recommended for advanced users, as it involves more
prerequisites and interaction with externally managed components which are out
of scope for these Retool blueprints modules.

## Prerequisites

* **`alb_internal = true`** — required to build the ALB in the private subnets
  instead of the default internet-facing ALB in the public subnets.
* **An externally issued ACM certificate ARN for `domain_name`** — an internal
  ALB cannot use a certificate this module mints, so supply one via
  `acm_certificate_arn` (covering `domain_name` and its wildcard, if used).
* **The list of desired CIDRs to allowlist (optional)** — the approved
  corporate, VPN, and connected AWS network ranges. If omitted, the ALB is
  reachable from the whole VPC CIDR.
* **A choice of DNS zone/record management** — a private zone this module
  creates, an existing corporate-managed zone, or fully external DNS. See
  [DNS](#dns) below.

The VPC must have private subnets (one per AZ), and the `vpc` input must carry
`private_subnet_ids` and `vpc_cidr_block` (`module.vpc.outputs` supplies both).
The approved networks must already be able to route to those private subnets
(VPN, Transit Gateway, VPC peering, or similar); that network path is out of
scope for the `aws-user-ingress` module.

## Configuration

### Internal ALB and allowlist

```hcl
module "user-ingress" {
  source  = "tryretool/self-hosted-blueprints/retool//modules/aws-user-ingress"
  version = "~> 0.6"

  domain_name           = "retool.internal.example.com"
  enable_https_listener = true

  alb_internal            = true
  alb_ingress_cidr_blocks = ["10.0.0.0/8", "172.20.0.0/16", "192.168.0.0/16"]

  acm_certificate_arn = "arn:aws:acm:us-west-2:123456789012:certificate/abc-123"

  vpc             = module.vpc.outputs
  eks             = module.eks.outputs
  retool_services = module.retool-services.outputs
}
```

Every CIDR in the allowlist may reach ports 443 (and 80, which redirects to
443). IPv6 ranges go in `alb_ingress_ipv6_cidr_blocks`.

When `alb_ingress_cidr_blocks` is left unset, an internal ALB defaults to the
VPC CIDR — reachable from the entire VPC. Set the allowlist explicitly to scope
it to just the approved networks.

### DNS

Pick one of the following.

**A. Private zone created by the module.** The module creates a private Route 53
zone named `domain_name`, associates it with the module's VPC, and writes the
ALB alias records into it:

```hcl
  create_hosted_zone  = true
  private_hosted_zone = true
```

**B. Existing corporate-managed zone.** The module writes alias records into a
zone you own but creates no zone:

```hcl
  create_hosted_zone = false
  hosted_zone_id     = "Z0123456789ABCDEFGHIJ"
```

**C. Fully external DNS.** Manage no records in Terraform and point DNS at the
`alb_dns_name` output yourself:

```hcl
  create_hosted_zone = false
  hosted_zone_id     = null
```

A private zone cannot validate a public ACM certificate, so option A requires
`acm_certificate_arn` (or `enable_https_listener = false`). The module fails the
plan with an explanatory precondition if you try to combine them.

## Caveats

* A private zone created here is associated with the module's VPC **only**.
  Resolving it from peered/transit-gateway VPCs or on-premises DNS requires DNS
  forwarding, or a zone managed by your corporate DNS and supplied via
  `hosted_zone_id`.
* The allowlist is CIDR-based. If your access model is expressed as a source
  security group (for example, one attached to a VPN or TGW endpoint), translate
  it to the corresponding CIDRs, or open an issue to add a
  security-group-source ingress allowlist.
* The CIDR allowlists apply to the ALB security group. Target-side reachability
  (the EKS node security group) is already scoped to the ALB's security group by
  the module.
