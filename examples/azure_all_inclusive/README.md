# Azure all-inclusive example

Deploys a complete self-hosted Retool stack on Azure: a VNet (with a shared Key
Vault), an AKS cluster, an Azure Database for PostgreSQL Flexible Server,
secrets in Key Vault, user ingress, and the Retool Helm release.

See the [repository README](../../README.md) for general prerequisites and
Terraform basics.

## Quick start

```sh
mv provider.example.tf provider.tf
# edit the locals block in main.tf:
#   subscription_id, prefix, location, resource_group_name, domain_name
az login   # if you haven't already
terraform init
terraform plan
terraform apply
```

## Configure DNS

The `azure-user-ingress` module created an Azure DNS zone for your `domain_name`
and, inside it, the `A` record pointing at the Application Gateway's public IP.
The only manual step is **delegating your domain to that zone**.

1. Get the DNS zone's name servers:

   ```sh
   terraform output -json modules | jq -r '.["user-ingress"].zone_name_servers[]'
   ```

2. At your domain registrar (or the DNS provider for the parent domain), create
   or update the **`NS` record** for `domain_name` to point at those name
   servers.

3. Wait for DNS to propagate — `dig +short NS <domain_name>` should print the
   zone's name servers from step 1 once the change has propagated. After that,
   `domain_name` reaches the Application Gateway.

   The Application Gateway public IP the domain should resolve to, for reference:

   ```sh
   terraform output -json modules | jq -r '.["user-ingress"].public_ip_address'
   ```

4. Enable HTTPS. This example defaults to `enable_https = true`, so once DNS
   resolves (step 3) cert-manager's Let's Encrypt issuer mints the TLS
   certificate automatically and `https://<domain_name>` works — no extra apply
   needed. Set `enable_https = false` to bring the deployment up over HTTP before
   DNS is ready.

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
