# AWS all-inclusive example

Deploys a complete self-hosted Retool stack on AWS: a VPC, an EKS cluster
(with Karpenter and the ALB controller), an RDS (Postgres) instance, secrets in
Secrets Manager, user ingress, and the Retool Helm release.

See the [repository README](../../README.md) for general prerequisites and
Terraform basics.

## Quick start

```sh
cp provider.tf.example provider.tf
# edit the locals block in main.tf: prefix, aws_profile, region, domain_name
aws sso login --profile <your-profile>   # or otherwise authenticate
terraform init
terraform plan
terraform apply
```

## Configure DNS

The `aws-user-ingress` module created a Route 53 hosted zone for your
`domain_name` and, inside it, the alias `A` record pointing at the load balancer
(plus the ACM certificate-validation records when HTTPS is enabled). The only
manual step is **delegating your domain to that hosted zone**.

1. Get the hosted zone's name servers:

   ```sh
   terraform output -json modules | jq -r '.["user-ingress"].zone_name_servers[]'
   ```

2. At your domain registrar (or the DNS provider for the parent domain), create
   or update the **`NS` record** for `domain_name` to point at those name
   servers.

3. Wait for DNS to propagate. Running `dig +short NS <domain_name>` should print
   the zone's name servers from step 1 once the change has propagated. After
   that, `domain_name` reaches the load balancer.

4. Enable HTTPS. This example starts with `enable_user_ingress_https = false`
   (HTTP only). Now that DNS is delegated, flip it to `true` and run
   `terraform apply` again — ACM can then validate the certificate via the
   delegated hosted zone and serve HTTPS. Retool's cookie settings follow the
   same flag (secure cookies require HTTPS).

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
