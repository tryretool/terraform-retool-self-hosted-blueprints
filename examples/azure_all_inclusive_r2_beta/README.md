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
cp provider.tf.example provider.tf
# edit the locals block in main.tf:
#   subscription_id, prefix, location, resource_group_name, domain_name
az login   # if you haven't already
terraform init
terraform plan
terraform apply
```

## Configure DNS

Same as the [base example](../azure_all_inclusive/README.md#configure-dns). The
`azure-user-ingress` module manages the `A` record (→ Application Gateway public
IP) inside an Azure DNS zone; you only need to **delegate your domain** to it.

1. Get the DNS zone's name servers:

   ```sh
   terraform output -json modules | jq -r '.["user-ingress"].zone_name_servers[]'
   ```

2. At your registrar (or parent-domain DNS provider), point the **`NS` record**
   for `domain_name` at those name servers.

3. Wait for DNS to propagate — `dig +short NS <domain_name>` should print the
   zone's name servers from step 1 once the change has propagated. After that,
   `domain_name` reaches the Application Gateway.

4. Enable HTTPS. This example defaults to `enable_https = true`, so once DNS
   resolves (step 3) cert-manager's Let's Encrypt issuer mints the TLS
   certificate automatically and `https://<domain_name>` works — no extra apply
   needed. Set `enable_https = false` to bring the deployment up over HTTP before
   DNS is ready.

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
