## `gcp-retool-services` module

This is a Terraform module providing the per-deployment supporting services recommended for running Retool self-hosted on GKE. Everything it creates belongs to one Retool deployment, so it can be instantiated several times against a single cluster.

* Creates the `<prefix>-retool` namespace the deployment lives in, and exports its name so `retool-helm` and `gcp-user-ingress` use the same one
* Provisions the Retool secrets in Google Secret Manager
* Creates the `<prefix>-eso` Google service account with access to just this deployment's secrets, and the Kubernetes service account that the cluster's shared External Secrets Operator impersonates to reach them
* Creates a namespaced ESO `SecretStore` and the `ExternalSecret` resources, so Secret Manager remains the source of truth
* Optionally creates a GCS bucket and credentials for Remote Repository storage

The cluster-wide operators — the External Secrets Operator and reloader — are cluster singletons installed once per cluster by [`gcp-gke`](../gcp-gke), not by this module.

### R² app hostnames

`enable_apps_domain = true` serves R² published apps at
`https://<app>.apps.<domain_name>/`, and `enable_wildcard_sandboxes = true` also
serves each editor preview at `sandbox-<id>.sandboxes.apps.<domain_name>`. Both
flow through `outputs` to `retool-helm` and the user-ingress module, which do the
work. They need `enable_agent_sandbox` and R² storage. See the root README.

> [!NOTE] This module is intended to be used in conjunction with the other GCP-specific modules in [`retool-self-hosted-blueprints`](https://github.com/tryretool/retool-self-hosted-blueprints). See the [usage examples](https://github.com/tryretool/retool-self-hosted-blueprints/tree/main/examples) for references on how to use this module.
