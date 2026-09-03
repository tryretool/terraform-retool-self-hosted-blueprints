# Azure — two Retool instances in one AKS cluster

A worked example of the pattern described in
**[`guides/shared-clusters.md`](../../guides/shared-clusters.md)** — read that
first. It explains which modules are shared, which are per-instance, and why.
This example is that guidance written out for Azure.

It stands up one VNet and one AKS cluster, then deploys two independent Retool
instances into them — `myretool-dev` and `myretool-prod`, each with its own
prefix, database, namespace, domain and Application Gateway.

| File | Contents |
|---|---|
| `shared.tf` | the VNet and the cluster, instantiated once |
| `myretool-dev.tf` | everything belonging to the dev instance |
| `myretool-prod.tf` | everything belonging to the prod instance |

Adding a third instance means copying `myretool-prod.tf` and changing the prefix
and domain. `shared.tf` does not change.

Note that AGIC is per-instance rather than shared: it binds one-to-one to an
Application Gateway, so each instance gets its own gateway, its own AGIC release
and its own IngressClass.

## Before you apply

1. Copy `provider.example.tf`.
2. In `shared.tf`, set `subscription_id`, `prefix_global`, `location` and
   `resource_group_name`.
3. In each `myretool-*.tf`, set `domain_name` and `license_key`.

Then the usual `terraform init` / `plan` / `apply`. Both instances come up in one
apply; nothing needs to be applied in stages.

With `enable_https = true`, an instance won't serve traffic until you delegate
DNS for its domain — the certificate can't validate before the NS records exist.

## See also

- [Using a shared/existing Kubernetes cluster](../../guides/shared-clusters.md) —
  including how to deploy into a cluster you already run, and how to share one
  Postgres instance between Retool instances.
- [Upgrades](../../guides/upgrade-v0.md)
- [Troubleshooting](../../guides/troubleshooting.md)
- [Scaling](../../guides/scaling.md)
