# Azure — deploy into a shared / existing AKS cluster

Deploys Retool into a pre-existing AKS cluster rather than creating one. It
deploys only the Retool-specific pieces into dedicated, prefixed namespaces and
assumes the cluster already runs the common operators (External Secrets
Operator, cert-manager) and an ingress controller.

Read [`guides/shared-clusters.md`](../../guides/shared-clusters.md) first — it
explains the namespace model, the `enable_*` toggles, and how to grant the
platform's ESO access to Retool's secrets.

## Cluster prerequisites

- Workload Identity / OIDC issuer enabled (used by ESO).
- An ingress controller and a cert-manager `ClusterIssuer` already present (this
  example sets `enable_agic = false` and `enable_cert_manager = false`).

## Before you apply

1. Copy `provider.example.tf` and set your subscription.
2. In `main.tf`, set the `locals` for your existing infrastructure: `cluster_name`,
   `vnet_id`, `postgres_subnet_id`, `key_vault_id`, `key_vault_uri`,
   `ingress_class_name`, `cluster_issuer_name`, and `domain_name`.
3. Grant the platform's External Secrets Operator access to Key Vault: federate
   its service account to `module.retool-services.outputs.eso_identity_client_id`
   (or grant its identity the same Key Vault access policy).
4. Point DNS for `domain_name` at your ingress controller's address (this example
   does not create the Application Gateway or its DNS A records).

To instead let this module create an Application Gateway + AGIC and cert-manager
(as the all-inclusive example does), drop the `enable_agic`,
`enable_cert_manager`, `ingress_class_name`, and `cluster_issuer_name` overrides.
