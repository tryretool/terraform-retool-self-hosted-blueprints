## `azure-aks` module

This is a Terraform module which provisions an AKS (Azure Kubernetes Service) cluster with defaults tuned for production Retool self-hosted deployments.

* Creates an AKS cluster with system-assigned managed identity
* Configures Workload Identity (OIDC issuer) for secure pod-to-Azure-service authentication
* Uses standard Azure CNI networking for Application Gateway Ingress Controller compatibility
* Creates a Log Analytics workspace for cluster monitoring
* Configures an auto-scaling default node pool

Alongside the cluster it installs the cluster-wide operators a Retool deployment needs:

* The [External Secrets Operator](https://external-secrets.io/latest/) (`enable_external_secrets`), in the `external-secrets` namespace
* [cert-manager](https://cert-manager.io/) (`enable_cert_manager`), which `azure-user-ingress` uses to issue Let's Encrypt certificates via DNS-01 against Azure DNS
* [Stakater reloader](https://github.com/stakater/Reloader) (`enable_reloader`), which restarts workloads when the ConfigMaps and Secrets they reference change

All three are **cluster-wide singletons**: each owns CRDs, admission webhooks and/or ClusterRoles whose names are fixed by the chart, so exactly one copy can exist per cluster and none can be installed once per Retool deployment. Each has an enable toggle so a cluster that already runs one can be adopted without a second copy fighting over it.

The operators hold no Azure permissions of their own. Each Retool deployment creates its own managed identity — for Key Vault, and for DNS on its own zone — and federates it to the controller's service account, so one deployment can never reach another's secrets or DNS records.

AGIC is deliberately **not** here: it binds 1:1 to an Application Gateway, so `azure-user-ingress` runs one per deployment, confined to its own IngressClass and namespace.

## Deploying into an existing cluster

Set `existing_cluster` to adopt a cluster this module did not create. No cluster,
network or node pool is created; the cluster's attributes are read from the live
cluster and only the operators above are installed. Instantiate the module **once
per cluster**, then deploy `azure-retool-services` + `retool-helm` + `azure-user-ingress` once per Retool
instance. See [`guides/shared-clusters.md`](../../guides/shared-clusters.md) and
[`examples/azure_shared_cluster`](../../examples/azure_shared_cluster).

The adopted cluster must have `oidc_issuer_enabled` and `workload_identity_enabled` set — every identity Retool creates federates against that issuer. This is checked at plan time.

> [!NOTE] This module is designed to be used in conjunction with the other Azure-specific modules in [`retool-self-hosted-blueprints`](https://github.com/tryretool/retool-self-hosted-blueprints). See the [usage examples](https://github.com/tryretool/retool-self-hosted-blueprints/tree/main/examples) for references on how to use this module.
