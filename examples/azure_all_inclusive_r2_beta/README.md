# Azure all-inclusive example (R2 beta)

Same complete Azure stack as [`azure_all_inclusive`](../azure_all_inclusive),
with the R2 features enabled: the **agent sandbox** (`enable_agent_sandbox`),
**Remote Repository Blob storage** (`enable_rr_blob`), and the unreleased **`r2`
Helm chart branch**.

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
# edit the locals block in main.tf:
#   subscription_id, prefix, location, resource_group_name, domain_name
az login   # if you haven't already
terraform init
terraform plan
terraform apply
```

A new deployment's certificate can't validate until DNS is delegated; see the
[base example](../azure_all_inclusive/README.md#quick-start) for the
`enable_https` note.

## Setting the license key

This example sets `license_key` inline for convenience. The recommended,
state-free path is to leave it unset, store the key in a Key Vault secret you
own (same shared vault), and point `license_key_secret_path` at its name:

```sh
az keyvault secret set \
  --vault-name <your-key-vault-name> \
  --name retool-<prefix>-license-key \
  --value '<your-license-key>'
```

```hcl
module "retool-services" {
  # ...
  license_key_secret_path = "retool-<prefix>-license-key"
}
```

## Scaling

See the [scaling guide](../../guides/scaling.md).
