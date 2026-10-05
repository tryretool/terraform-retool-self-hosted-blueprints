variable "domain_name" {
  type        = string
  description = "Desired retool domain name"
}

variable "vpc" {
  type = object({
    vpc_id             = string
    vpc_cidr_block     = optional(string)
    public_subnet_ids  = optional(list(string))
    private_subnet_ids = optional(list(string))
  })
  description = <<-EOD
    VPC related inputs:
      vpc_id: VPC where the load balancer and target group are created
      vpc_cidr_block: VPC CIDR block; used as the default ALB ingress allowlist
        when alb_internal is true and alb_ingress_cidr_blocks is null
      public_subnet_ids: Subnet IDs (one per AZ) the internet-facing ALB is placed in
      private_subnet_ids: Subnet IDs (one per AZ) the internal ALB is placed in
        when alb_internal is true

    module.vpc.outputs supplies every attribute; only the ones relevant to the
    selected scheme (alb_internal) need to be populated.
  EOD
}

variable "alb_internal" {
  type        = bool
  description = <<-EOT
    When true, create an internal (private) Application Load Balancer in
    vpc.private_subnet_ids. When false (default), create an internet-facing ALB
    in vpc.public_subnet_ids.

    This is a create-time attribute: changing it replaces the ALB, so switching
    an existing deployment from public to internal is a cutover and the new ALB
    gets a new DNS name.
  EOT
  default     = false
}

variable "alb_ingress_cidr_blocks" {
  type        = list(string)
  description = <<-EOT
    IPv4 CIDRs allowed to reach the ALB on ports 443 and 80.

    When null (default), resolves to the VPC CIDR (vpc.vpc_cidr_block) if
    alb_internal is true, otherwise to ["0.0.0.0/0"]. Internal deployments
    should set this to the approved corporate, VPN, and connected AWS network
    CIDRs so the ALB is not reachable from the whole VPC by default.
  EOT
  default     = null
}

variable "alb_ingress_ipv6_cidr_blocks" {
  type        = list(string)
  description = "IPv6 CIDRs allowed to reach the ALB on ports 443 and 80. Defaults to none."
  default     = []
}

variable "eks" {
  type = object({
    node_security_group_id = string
  })
  description = <<-EOD
    EKS related inputs:
      node_security_group_id: EKS worker node security group ID; must allow TCP from the user ALB to reach pod IPs registered by TargetGroupBinding
  EOD
}

variable "retool_service_name" {
  type        = string
  description = "Name of the Kubernetes Service fronting Retool pods"
  default     = "retool"
}

variable "retool_services" {
  type = object({
    retool_namespace = optional(string)
  })
  default     = null
  description = "Retool-services outputs (e.g. module.retool-services.outputs). The TargetGroupBinding is created in retool_namespace so it sits beside the Retool Service. When null (or retool_namespace unset), falls back to the \"default\" namespace."
}

variable "retool_service_port" {
  type        = number
  description = "Port on the Kubernetes Service that serves Retool traffic"
  default     = 3000
}

variable "enable_https_listener" {
  type        = bool
  description = <<-EOT
    When true, request an ACM certificate (plus DNS validation records in this
    hosted zone) and attach an HTTPS listener on port 443. The certificate must
    reach ISSUED state (requires delegating the hosted zone NS at the registrar
    unless the domain is already publicly resolvable).
    When false, no ACM certificate is created and the ALB serves Retool on HTTP
    port 80 only — suitable for first apply before DNS delegation, sandbox
    domains that cannot publicly validate, or TLS termination elsewhere.

    Set acm_certificate_arn to attach an existing certificate instead of minting
    a new one.
  EOT
  default     = false
}

variable "acm_certificate_arn" {
  type        = string
  description = <<-EOT
    ARN of an existing ACM certificate to attach to the HTTPS listener. When set,
    this module creates no certificate and no DNS validation records — useful
    when the certificate is issued and renewed centrally (e.g. by a parent org)
    rather than by this stack. Only consulted when enable_https_listener is true.
  EOT
  default     = null
}

variable "create_hosted_zone" {
  type        = bool
  description = <<-EOT
    Whether to create a public Route53 hosted zone for domain_name. Set false
    when the domain's DNS is managed elsewhere; then supply hosted_zone_id to
    have this module still write the ALB alias records into an existing zone, or
    leave it null to have this module manage no DNS at all (you point the domain
    at the alb_dns_name output yourself).
  EOT
  default     = true
}

variable "hosted_zone_id" {
  type        = string
  description = <<-EOT
    ID of an existing Route53 hosted zone to write the ALB alias records (and, if
    this module mints a certificate, the ACM validation records) into. Only used
    when create_hosted_zone is false. Leave null for fully external DNS.
  EOT
  default     = null
}

variable "private_hosted_zone" {
  type        = bool
  description = <<-EOT
    When create_hosted_zone is true, create a private (VPC-associated) Route53
    zone instead of a public one. Ignored when create_hosted_zone is false.

    A private hosted zone cannot satisfy a public ACM DNS validation, so this
    cannot be combined with a certificate minted by this module. Supply
    acm_certificate_arn (an existing certificate) or set
    enable_https_listener = false.

    The zone is associated only with vpc_id. Reaching it from peered/transit
    gateway VPCs requires DNS forwarding or a corporate-managed zone supplied
    via hosted_zone_id with create_hosted_zone = false.
  EOT
  default     = false
}

variable "alb_authenticate_oidc" {
  type = object({
    issuer                              = string
    authorization_endpoint              = string
    token_endpoint                      = string
    user_info_endpoint                  = string
    client_id                           = string
    client_secret                       = string
    scope                               = optional(string, "openid")
    session_cookie_name                 = optional(string, "AWSELBAuthSessionCookie")
    session_timeout                     = optional(number, 604800)
    on_unauthenticated_request          = optional(string, "authenticate")
    authentication_request_extra_params = optional(map(string), {})
  })
  description = <<-EOT
    When set, the HTTPS listener authenticates users against this OIDC identity
    provider before forwarding to Retool (an ordered authenticate-oidc → forward
    default action). This is edge authentication in front of Retool, independent
    of Retool's own SSO. Requires enable_https_listener.
  EOT
  default     = null
  sensitive   = true
}
