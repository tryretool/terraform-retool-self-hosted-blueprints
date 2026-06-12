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
cp provider.example.tf provider.tf
# edit the locals block in main.tf: prefix, aws_profile, region, domain_name
aws sso login --profile <your-profile>   # or otherwise authenticate
terraform init
terraform plan
terraform apply
```

Once DNS is delegated, enable HTTPS as described in the
[base example](../aws_all_inclusive/README.md#quick-start).

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
