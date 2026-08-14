# Inputs for the CloudFormation → Terraform migration stack.
#
# Copy vars.tf.example to terraform.tfvars and fill it in. Most values come
# straight off your existing CloudFormation stack's parameters and resources.

# ---------------------------------------------------------------------------
# Deployment identity
# ---------------------------------------------------------------------------

variable "prefix" {
  type        = string
  description = "Prefix for resource names. Also becomes the EKS cluster name (truncated to 38 characters) and the retool/{prefix}/* Secrets Manager namespace. Pick something distinct from your CloudFormation stack name so the two deployments never collide."

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]*$", var.prefix))
    error_message = "prefix must be lowercase alphanumeric with hyphens, starting with a letter or digit."
  }
}

variable "region" {
  type        = string
  description = "AWS region. Must be the region your existing VPC and RDS instance live in."
}

variable "aws_profile" {
  type        = string
  description = "AWS CLI profile used by the provider and by the `aws eks get-token` exec credential helper."
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to everything this stack creates."
  default     = {}
}

variable "domain_name" {
  type        = string
  description = "Domain that serves Retool to end users, without a scheme (e.g. \"retool.example.com\"). This is the CloudFormation stack's BaseDomain minus the https:// prefix."
}

# ---------------------------------------------------------------------------
# Existing network (CloudFormation-managed)
# ---------------------------------------------------------------------------

variable "vpc_id" {
  type        = string
  description = "ID of the existing VPC to deploy into — the CloudFormation stack's VpcId parameter."
}

variable "private_subnet_ids" {
  type        = list(string)
  description = <<-EOT
    Subnets for the EKS control plane, worker nodes, and Karpenter-provisioned
    capacity — the CloudFormation stack's SubnetId parameter. Must span at least
    two availability zones, and must have outbound internet access (a NAT
    gateway, or VPC endpoints for ECR/S3 plus egress to charts.retool.com) so
    nodes can pull images.

    This stack tags these subnets for Karpenter discovery; see existing-network.tf.
  EOT

  validation {
    condition     = length(var.private_subnet_ids) >= 2
    error_message = "EKS requires subnets in at least two availability zones."
  }
}

variable "public_subnet_ids" {
  type        = list(string)
  description = "Subnets for the internet-facing user ALB — the CloudFormation stack's LoadBalancerSubnetId parameter. Must span at least two availability zones and route to an internet gateway."

  validation {
    condition     = length(var.public_subnet_ids) >= 2
    error_message = "An Application Load Balancer requires subnets in at least two availability zones."
  }
}

variable "manage_karpenter_subnet_tags" {
  type        = bool
  description = "Whether to tag the private subnets with karpenter.sh/discovery. Karpenter selects subnets by this tag and cannot launch nodes without it, so leave this true unless you apply the tag by other means — for example because the subnets are declared in a CloudFormation template that would revert it. The tag value must be the EKS cluster name (var.prefix truncated to 38 characters)."
  default     = true
}

variable "tag_subnets_for_load_balancer_discovery" {
  type        = bool
  description = "Whether to add the kubernetes.io/role/elb and kubernetes.io/role/internal-elb tags to the public and private subnets. The user ALB in this stack names its subnets explicitly and does not need them, but they let the AWS Load Balancer Controller auto-discover subnets for any Ingress you create later. Leave false if these subnets are shared with workloads that would be disrupted by the tags."
  default     = false
}

# ---------------------------------------------------------------------------
# Existing Retool database (CloudFormation-managed)
# ---------------------------------------------------------------------------

variable "db" {
  type = object({
    instance_identifier   = string
    credentials_secret_id = string
    password_property     = optional(string, "password")
    security_group_id     = optional(string)
  })
  description = <<-EOT
    The existing Retool RDS instance, which holds all your data and is *not*
    recreated by this stack.

      instance_identifier:   RDS DB instance identifier (not the endpoint).
                             Host, port, database name and master username are
                             read from it.
      credentials_secret_id: Secrets Manager secret ID/ARN holding the master
                             credentials — the CloudFormation stack's
                             RetoolRDSSecret, whose value is
                             {"username": "...", "password": "..."}.
      password_property:     JSON property within that secret holding the
                             password. Defaults to "password".
      security_group_id:     Security group attached to the instance. When set,
                             this stack adds an ingress rule allowing Postgres
                             from the EKS nodes. Leave null if you manage that
                             rule yourself.
  EOT
}

# ---------------------------------------------------------------------------
# Existing Retool secrets (CloudFormation-managed)
# ---------------------------------------------------------------------------

variable "encryption_key_secret" {
  type = object({
    secret_id = string
    property  = optional(string, "password")
  })
  description = <<-EOT
    The existing Retool encryption key — the CloudFormation stack's
    RetoolEncryptionKeySecret. This MUST be carried over: credentials stored in
    the Retool database are encrypted with it, and a fresh key makes every saved
    resource credential undecryptable.

    `property` is the JSON key within the secret; CloudFormation's
    GenerateSecretString nests the value under "password".
  EOT
}

variable "jwt_secret" {
  type = object({
    secret_id = string
    property  = optional(string, "password")
  })
  description = "The existing Retool JWT secret — the CloudFormation stack's RetoolJWTSecret. Carrying it over keeps existing user sessions valid across the cutover. Set to null to have Terraform generate a new one (all users are signed out)."
  default     = null
}

variable "license_key_secret" {
  type = object({
    secret_id = string
    property  = optional(string)
  })
  description = "Secrets Manager secret holding the Retool license key — the CloudFormation stack's LicenseKeyARN, whose value is JSON with the key under `licenseKey`. Set `property = null` if your secret holds the bare key string. Leave the whole object null to run without a license."
  default     = null
}

# ---------------------------------------------------------------------------
# Cluster
# ---------------------------------------------------------------------------

variable "cluster_version" {
  type        = string
  description = "EKS Kubernetes version."
  default     = "1.32"
}

variable "cluster_encryption_kms_key_arn" {
  type        = string
  description = "Existing KMS key for EKS secret encryption. Leave null to have the aws-eks module create one. Set this if your organization mandates a specific CMK — it cannot be changed after the cluster is created."
  default     = null
}

variable "eks_additional_access_entries" {
  type        = map(any)
  description = "Additional EKS access entries, keyed by IAM principal ARN. Use this to grant your team kubectl access beyond the identity that runs terraform apply."
  default     = {}
}

# ---------------------------------------------------------------------------
# Ingress: certificate, DNS, and edge authentication
# ---------------------------------------------------------------------------

variable "enable_https" {
  type        = bool
  description = "Whether the load balancer terminates TLS on port 443. Retool's cookie security follows this flag, so it must match reality: secure cookies require HTTPS to the browser. Set false only if you need a first apply before a certificate is available."
  default     = true
}

variable "acm_certificate_arn" {
  type        = string
  description = "ARN of the existing ACM certificate to serve Retool's TLS — the CloudFormation stack's CertificateARN. Leave null to have the user-ingress module create a Route53 zone and mint its own certificate (only workable if you can delegate the domain's DNS to that zone)."
  default     = null
}

variable "hosted_zone_id" {
  type        = string
  description = "Existing Route53 hosted zone to write the ALB alias records into. Leave null when DNS is managed outside AWS or by another team — you then point domain_name at the alb_dns_name output yourself."
  default     = null
}

variable "alb_oidc" {
  type = object({
    issuer                     = string
    authorization_endpoint     = string
    token_endpoint             = string
    user_info_endpoint         = string
    credentials_secret_id      = string
    client_id_property         = optional(string, "clientId")
    client_secret_property     = optional(string, "clientSecret")
    scope                      = optional(string, "openid")
    session_timeout            = optional(number, 604800)
    on_unauthenticated_request = optional(string, "authenticate")
  })
  description = <<-EOT
    Edge authentication at the load balancer: users complete an OIDC flow before
    any request reaches Retool. This mirrors the CloudFormation stack's
    authenticate-oidc listener action. Leave null to serve Retool directly and
    rely on Retool's own authentication.

    credentials_secret_id is a Secrets Manager secret holding the OIDC client
    credentials — the CloudFormation stack's AlbOAuthARN. Note that Terraform
    reads this secret to configure the listener, so its value lands in Terraform
    state; use an encrypted, access-restricted backend.
  EOT
  default     = null
}

# ---------------------------------------------------------------------------
# Temporal (Retool Workflows)
# ---------------------------------------------------------------------------

variable "temporal" {
  type = object({
    host                  = string
    port                  = optional(number, 5432)
    username              = string
    credentials_secret_id = string
    password_property     = optional(string, "password")
    security_group_id     = optional(string)
    database              = optional(string, "temporal")
    visibility_database   = optional(string, "temporal_visibility")
    tls_enabled           = optional(bool, true)
    num_history_shards    = optional(number, 128)
    image_repository      = optional(string, "tryretool/one-offs")
    image_tag             = optional(string, "retool-temporal-1.1.6")
    enable_web_ui         = optional(bool, false)
  })
  description = <<-EOT
    Self-hosted Temporal, backed by an existing Postgres — the CloudFormation
    stack's RetoolTemporalRDSCluster. The Retool Helm chart runs the Temporal
    cluster itself (via its retool-temporal-services-helm subchart), so only the
    database is brought over.

      host / port:           writer endpoint of the existing Aurora cluster or
                             RDS instance.
      username:              master username.
      credentials_secret_id: Secrets Manager secret holding the password (the
                             CloudFormation stack's RetoolTemporalRDSSecret).
                             Synced into the cluster as a Kubernetes Secret; see
                             temporal.tf.
      security_group_id:     when set, this stack adds an ingress rule allowing
                             Postgres from the EKS nodes.
      database /
      visibility_database:   Temporal creates these on startup if absent.

    Set to null to run Retool without Workflows.
  EOT
  default     = null
}

# ---------------------------------------------------------------------------
# CloudAuth (Amazon-internal)
# ---------------------------------------------------------------------------

variable "cloudauth" {
  type = object({
    vpc_endpoint_service_name = string
    fqen                      = string
    subdomain                 = optional(string, "oauth.cloudauth.a2z.com")
    api_gateway_account_ids   = optional(list(string), [])
  })
  description = <<-EOT
    Amazon-internal CloudAuth private integration. Creates an interface VPC
    endpoint to the CloudAuth PrivateLink service, a private hosted zone
    resolving `subdomain` to it, an IAM policy granting execute-api:Invoke on the
    CloudAuth accounts, and an EKS Pod Identity association so the Retool pods
    assume that role. Also injects the DEPENDENCIES and CloudAuthFQEN
    environment variables the application reads.

    Leave null unless you are migrating an Amazon-internal deployment; nothing
    here applies to a standard Retool install.
  EOT
  default     = null
}

# ---------------------------------------------------------------------------
# Retool application configuration
# ---------------------------------------------------------------------------

variable "retool_image_tag" {
  type        = string
  description = "Retool backend image tag, e.g. \"4.0.9-stable\". Match the tag your CloudFormation stack runs so the migration changes one thing at a time; upgrade afterwards."
}

variable "retool_helm_chart_version" {
  type        = string
  description = "Version of the Retool Helm chart to deploy."
  default     = "6.11.6"
}

variable "replica_counts" {
  type = object({
    backend           = optional(number, 2)
    workflows_backend = optional(number, 1)
    workflows_worker  = optional(number, 1)
    code_executor     = optional(number, 1)
  })
  description = "Replica counts per Retool service. Start from the CloudFormation stack's DesiredCount / DesiredWorkflowsCount / DesiredCodeExecutorCount. There is no jobs runner entry: the chart always runs exactly one."
  default     = {}
}

variable "usage_api_token" {
  type        = string
  description = "Retool usage reporting token — the CloudFormation stack's UsageAPIToken. Rendered as a plain environment variable in the Helm release, so it is stored in Terraform state; leave null and add USAGE_API_TOKEN to the retool/{prefix}/extra-env-vars secret instead if that matters to you."
  default     = null
  sensitive   = true
}

variable "ldap_role_mapping" {
  type        = string
  description = "LDAP group to Retool role mapping — the CloudFormation stack's LDAPRoleMapping, e.g. \"GRS-Tech-Admin->admin\"."
  default     = null
}

variable "enable_agent_sandbox" {
  type        = bool
  description = "Enable the Retool agent sandbox (R2). Not present in the CloudFormation stack; leave false for a like-for-like migration and turn it on afterwards."
  default     = false
}

variable "enable_rr_s3" {
  type        = bool
  description = "Create an S3 bucket for Retool Remote Repository storage (R2). Not present in the CloudFormation stack; leave false for a like-for-like migration."
  default     = false
}

variable "retool_helm_extra_values" {
  type        = list(string)
  description = "Additional Helm values documents (YAML strings) merged last, after everything this example renders. Use for anything not covered by a variable above."
  default     = []
}
