# Azure all-inclusive example

Deploys a complete self-hosted Retool stack on Azure: a VNet (with a shared Key
Vault), an AKS cluster, an Azure Database for PostgreSQL Flexible Server,
secrets in Key Vault, user ingress, and the Retool Helm release.

See the [repository README](../../README.md) for general prerequisites and
Terraform basics.

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

This example defaults to `enable_https = true`. A new deployment's certificate
can't validate until you delegate DNS (install the NS records) so the domain
resolves to the deployment. Set `enable_https = false` to allow HTTP first if
you want to bring it up before DNS is ready.

## Setting the license key

The recommended path keeps the key out of Terraform state: store it in a Key
Vault secret you own (in the same shared vault) and point the
`license_key_secret_path` input at its name. Create the secret:

```sh
az keyvault secret set \
  --vault-name <your-key-vault-name> \
  --name retool-<prefix>-license-key \
  --value '<your-license-key>'
```

Then set it on the `azure-retool-services` module and apply:

```hcl
module "retool-services" {
  # ...
  license_key_secret_path = "retool-<prefix>-license-key"
}
```

## Scaling

See the [scaling guide](../../guides/scaling.md) for sizing the Flexible Server
(`sku_name`, which also governs `max_connections`) and the Retool services.
