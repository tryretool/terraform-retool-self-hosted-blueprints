## `gcp-gke` module

This is a Terraform module which provisions a GKE cluster with defaults and options tuned for production Retool self-hosted deployments. Includes a node pool with autoscaling, Workload Identity, and the GKE Gateway API controller.

Alongside the cluster it installs the cluster-wide operators a Retool deployment needs:

* The [External Secrets Operator](https://external-secrets.io/latest/) (`enable_external_secrets`), in the `external-secrets` namespace
* [Stakater reloader](https://github.com/stakater/Reloader) (`enable_reloader`), which restarts workloads when the ConfigMaps and Secrets they reference change

Both are **cluster-wide singletons**: each owns CRDs and/or ClusterRoles whose names are fixed by the chart, so exactly one copy can exist per cluster and neither can be installed once per Retool deployment. Each has an enable toggle so a cluster that already runs one can be adopted without a second copy fighting over it.

The operators hold no Google API permissions of their own. Each Retool deployment creates its own service account and grants it access to just its own secrets, and names it on its `SecretStore` — so one deployment can never read another's.

## Deploying into an existing cluster

Set `existing_cluster` to adopt a cluster this module did not create. No cluster,
network or node pool is created; the cluster's attributes are read from the live
cluster and only the operators above are installed. Instantiate the module **once
per cluster**, then deploy `gcp-retool-services` + `retool-helm` + `gcp-user-ingress` once per Retool
instance. See [`guides/shared-clusters.md`](../../guides/shared-clusters.md) and
[`examples/gcp_shared_cluster`](../../examples/gcp_shared_cluster).

The adopted cluster must have Workload Identity enabled, and the Gateway API enabled if you use `gcp-user-ingress`. Both are checked at plan time.

> [!NOTE] This module is designed to be used in conjunction with the other GCP-specific modules in [`retool-self-hosted-blueprints`](https://github.com/tryretool/retool-self-hosted-blueprints). See the [usage examples](https://github.com/tryretool/retool-self-hosted-blueprints/tree/main/examples) for references on how to use this module.
