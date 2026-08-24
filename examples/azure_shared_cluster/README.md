# Azure — deploy into a shared / existing AKS cluster

Deploys Retool into a pre-existing AKS cluster rather than creating one. It
instantiates `azure-aks` with `existing_cluster`, which adopts the cluster and
installs only the cluster-wide operators Retool needs (External Secrets
Operator, cert-manager, reloader), and puts the Retool deployment itself in a
single `<prefix>-retool` namespace. Each operator has an `enable_*` toggle — turn
off whatever your platform team already runs. This example turns all three off,
because it assumes a cluster that already runs them.

AGIC is not a cluster singleton: it binds 1:1 to an Application Gateway, so each
deployment can run its own, confined to its own IngressClass and namespace. This
example instead brings its own ingress controller and sets `enable_agic = false`.

Read [`guides/shared-clusters.md`](../../guides/shared-clusters.md) first — it
explains the namespace model, why the operators are singletons, and how the
External Secrets Operator reaches Retool's secrets.

## Cluster prerequisites

- Workload Identity / OIDC issuer enabled — every identity Retool creates
  federates against that issuer. Checked at plan time.
- An ingress controller and a cert-manager `ClusterIssuer` already present, since
  this example sets `enable_agic = false` and `cluster_issuer_name`.

## Before you apply

1. Copy `provider.example.tf` and set your subscription.
2. In `main.tf`, set the `locals` for your existing infrastructure: `cluster_name`,
   `vnet_id`, `postgres_subnet_id`, `key_vault_id`, `key_vault_uri`,
   `ingress_class_name`, `cluster_issuer_name`, and `domain_name`.
3. Confirm no other Terraform state already owns the cluster-wide operators —
   only one may install them. If another Retool deployment already runs in this
   cluster, drop the `aks` module block and keep the rest.
4. Grant the platform's External Secrets Operator access to Key Vault: federate
   its service account to `module.retool-services.outputs.eso_identity_client_id`
   (or grant its identity the same Key Vault access policy).
5. Point DNS for `domain_name` at your ingress controller's address — this
   example creates no Application Gateway and no DNS A records.

To instead let this stack create an Application Gateway + AGIC and issue its own
certificate, flip `enable_agic` back on, drop `ingress_class_name` and
`cluster_issuer_name`, and set `enable_cert_manager = true` on `azure-aks`.

## See also

- [Upgrades](../../guides/upgrade-v0.md) — migrating an existing deployment.
- [Troubleshooting](../../guides/troubleshooting.md)
- [Scaling](../../guides/scaling.md)
