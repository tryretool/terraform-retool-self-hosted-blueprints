# Inputs for the CloudFormation → Terraform migration stack.
#
# These arrive from two files, kept separate so the machine-derived half can be
# regenerated at any time without disturbing your own choices:
#
#   imported.tfvars    written by import_from_cloudformation.py — everything
#                      discoverable from the CloudFormation stack
#   terraform.tfvars   your choices; start from vars.tf.example
#
#   terraform apply -var-file=imported.tfvars -var-file=terraform.tfvars

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
  description = "AWS region. Must be the region your existing VPC and databases live in."
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
# Existing network (referenced, not imported)
# ---------------------------------------------------------------------------
#
# The VPC stays outside Terraform's control. In the Retool CloudFormation
# templates the VPC and subnets are stack *parameters*, not stack resources —
# they were never CloudFormation-managed, so there is nothing to reclaim.

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
  description = "Whether to tag the private subnets with karpenter.sh/discovery. Karpenter selects subnets by this tag and cannot launch nodes without it, so leave this true unless you apply the tag by other means. The tag value must be the EKS cluster name (var.prefix truncated to 38 characters)."
  default     = true
}

# ---------------------------------------------------------------------------
# Existing databases (referenced, not managed)
# ---------------------------------------------------------------------------
#
# These stay outside Terraform's control. This stack reads their connection
# details and adds an ingress rule so the new EKS nodes can reach them; it never
# modifies the databases themselves, and never touches the existing security
# group rules the running ECS deployment depends on.

variable "retool_db" {
  type = object({
    instance_identifier   = string
    credentials_secret_id = string
    password_property     = optional(string, "password")
    security_group_id     = optional(string)
  })
  description = <<-EOT
    The existing Retool database, which holds all your data and is neither
    created nor modified by this stack.

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
# The Temporal database (Retool Workflows)
# ---------------------------------------------------------------------------

variable "temporal_db" {
  type = object({
    host                  = string
    port                  = optional(number, 5432)
    username              = string
    database              = optional(string, "temporal")
    credentials_secret_id = string
    password_property     = optional(string, "password")
    security_group_id     = optional(string)
  })
  description = <<-EOT
    The existing Temporal database — the CloudFormation stack's Temporal RDS
    instance or Aurora cluster. Referenced, never modified; the Retool Helm
    chart runs the Temporal cluster itself and only needs somewhere to store its
    state.

      host / port:           writer endpoint of the existing instance or cluster.
      username:              master username.
      credentials_secret_id: Secrets Manager secret holding the password (the
                             CloudFormation stack's RetoolTemporalRDSSecret).
                             Synced into the cluster as a Kubernetes Secret; see
                             temporal.tf.
      security_group_id:     when set, this stack adds an ingress rule allowing
                             Postgres from the EKS nodes.

    Set to null to run Retool without Workflows.
  EOT
  default     = null
}

variable "temporal" {
  type = object({
    visibility_database = optional(string, "temporal_visibility")
    tls_enabled         = optional(bool, true)
    num_history_shards  = optional(number, 128)
    image_repository    = optional(string, "tryretool/one-offs")
    image_tag           = optional(string, "retool-temporal-1.1.6")
    enable_web_ui       = optional(bool, false)
  })
  description = "Settings for the self-hosted Temporal cluster the Retool Helm chart runs. The database it connects to comes from temporal_db or temporal_db_external; these are the knobs that aren't part of the database itself."
  default     = {}
}

# ---------------------------------------------------------------------------
# Existing Retool secrets (referenced, not imported)
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
    GenerateSecretString nests the value under "password". Set it to null if the
    secret holds a bare string.
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
  description = "Whether the load balancer terminates TLS on port 443. Retool's cookie security follows this flag, so it must match reality: secure cookies require HTTPS to the browser."
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

    Terraform reads credentials_secret_id to configure the listener, so its value
    lands in Terraform state; use an encrypted, access-restricted backend.
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
  description = "Additional Helm values documents (YAML strings) merged last, after everything this example renders."
  default     = []
}
