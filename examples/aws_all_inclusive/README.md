# AWS all-inclusive example

Deploys a complete self-hosted Retool stack on AWS: a VPC, an EKS cluster
(with Karpenter and the ALB controller), an RDS (Postgres) instance, secrets in
Secrets Manager, user ingress, and the Retool Helm release.

See the [repository README](../../README.md) for general prerequisites and
Terraform basics.

## Quick start

```sh
cp provider.example.tf provider.tf
# edit the locals block in main.tf: prefix, aws_profile, region, domain_name
aws sso login --profile <your-profile>   # or otherwise authenticate
terraform init
terraform plan
terraform apply
```

This example starts with `enable_user_ingress_https = false` (HTTP only). Once
you've delegated DNS so the domain resolves to the load balancer, flip it to
`true` to provision an ACM certificate and serve HTTPS, then `terraform apply`
again. Retool's cookie settings follow the same flag (secure cookies require
HTTPS).

## Setting the license key

The recommended path keeps the key out of Terraform state: store it in a Secrets
Manager secret you own and point the `license_key_secret_path` input at it.
Create the secret:

```sh
aws secretsmanager create-secret \
  --name retool/<prefix>/license-key \
  --secret-string '<your-license-key>'
```

Then set it on the `aws-retool-services` module (name or ARN) and apply:

```hcl
module "retool-services" {
  # ...
  license_key_secret_path = "retool/<prefix>/license-key"
}
```

(Or — simplest but least secure — set `license_key = "..."` directly on that
module to have Terraform create and manage the secret for you.)

## Scaling

See the [scaling guide](../../guides/scaling.md) for sizing RDS
(`instance_class`, and `max_connections` via the `parameters` input) and the
Retool services.
