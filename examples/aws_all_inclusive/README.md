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

The recommended path keeps the key out of Terraform state. After the first
apply, add it to the deployment's extra-env-vars secret (write-only in
Terraform, so it is **not** reverted on later applies):

```sh
aws secretsmanager put-secret-value \
  --secret-id retool/<prefix>/extra-env-vars \
  --secret-string '{"LICENSE_KEY":"<your-license-key>"}'
```

Alternatively, point the `license_key_secret_path` input on the
`aws-retool-services` module at an existing Secrets Manager secret (name or
ARN), or — simplest but least secure — set `license_key = "..."` directly on
that module.

## Scaling

See the [scaling guide](../../guides/scaling.md) for sizing RDS
(`instance_class`, and `max_connections` via the `parameters` input) and the
Retool services.
