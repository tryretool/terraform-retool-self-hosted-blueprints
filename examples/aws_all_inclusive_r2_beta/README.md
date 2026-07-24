# AWS all-inclusive example (R2 beta)

Same complete AWS stack as [`aws_all_inclusive`](../aws_all_inclusive), with the
R2 features enabled: the **agent sandbox**, **Remote Repository S3 storage**,
and the unreleased **`r2` Helm chart branch**.

See the [repository README](../../README.md) for general prerequisites.

## Prerequisite: `helm-git`

This example sets `retool_helm_chart_use_unpublished_branch = "r2"`, which pulls
the Retool chart from git. That requires the
[`helm-git`](https://github.com/aslafy-z/helm-git) Helm plugin:

```sh
helm plugin install https://github.com/aslafy-z/helm-git
```

Without it, `terraform apply` fails when fetching the chart.

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

Same as the [base example](../aws_all_inclusive/README.md#configure-dns). The
`aws-user-ingress` module manages the alias `A` record (→ load balancer) and the
ACM validation records inside a Route 53 hosted zone; you only need to
**delegate your domain** to it.

1. Get the hosted zone's name servers:

   ```sh
   terraform output -json modules | jq -r '.["user-ingress"].zone_name_servers[]'
   ```

2. At your registrar (or parent-domain DNS provider), point the **`NS` record**
   for `domain_name` at those name servers.

3. Wait for DNS to propagate — `dig +short NS <domain_name>` should print the
   zone's name servers from step 1 once the change has propagated.

4. Enable HTTPS. This example starts with `enable_user_ingress_https = false`
   (HTTP only). Now that DNS is delegated, flip it to `true` and run
   `terraform apply` again — ACM can then validate the certificate via the
   delegated hosted zone and serve HTTPS. Retool's cookie settings follow the
   same flag (secure cookies require HTTPS).

## Setting the license key

Recommended (state-free) path — store the key in a Secrets Manager secret you
own and point `license_key_secret_path` at it (name or ARN):

```sh
aws secretsmanager create-secret \
  --name retool/<prefix>/license-key \
  --secret-string '<your-license-key>'
```

```hcl
module "retool-services" {
  # ...
  license_key_secret_path = "retool/<prefix>/license-key"
}
```

## Scaling

See the [scaling guide](../../guides/scaling.md).
