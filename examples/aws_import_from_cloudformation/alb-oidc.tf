# Edge authentication at the load balancer, mirroring the CloudFormation stack's
# authenticate-oidc listener action: users complete an OIDC flow with your
# identity provider before any request is forwarded to Retool.
#
# This is separate from, and additional to, Retool's own authentication.

# The listener needs the client credentials inline, so Terraform reads them here
# and they become part of Terraform state. Use a remote backend with encryption
# and restricted access. (The CloudFormation stack avoided this by resolving the
# secret at deploy time with {{resolve:secretsmanager:...}}, which has no
# equivalent in Terraform.)
data "aws_secretsmanager_secret_version" "alb_oidc" {
  count = var.alb_oidc != null ? 1 : 0

  secret_id = var.alb_oidc.credentials_secret_id
}

locals {
  alb_oidc_credentials = var.alb_oidc != null ? jsondecode(data.aws_secretsmanager_secret_version.alb_oidc[0].secret_string) : null

  alb_authenticate_oidc = var.alb_oidc == null ? null : {
    issuer                 = var.alb_oidc.issuer
    authorization_endpoint = var.alb_oidc.authorization_endpoint
    token_endpoint         = var.alb_oidc.token_endpoint
    user_info_endpoint     = var.alb_oidc.user_info_endpoint

    client_id     = local.alb_oidc_credentials[var.alb_oidc.client_id_property]
    client_secret = local.alb_oidc_credentials[var.alb_oidc.client_secret_property]

    scope                      = var.alb_oidc.scope
    session_timeout            = var.alb_oidc.session_timeout
    on_unauthenticated_request = var.alb_oidc.on_unauthenticated_request
  }
}
