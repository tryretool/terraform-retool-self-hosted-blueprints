## `gcp-gke` module

This is a Terraform module which provisions a GKE cluster with defaults and options tuned for production Retool self-hosted deployments. Includes a node pool with autoscaling, Workload Identity, and the GKE Gateway API controller.

> [!NOTE] This module is designed to be used in conjunction with the other GCP-specific modules in [`retool-self-hosted-blueprints`](https://github.com/tryretool/retool-self-hosted-blueprints). See the [usage examples](https://github.com/tryretool/retool-self-hosted-blueprints/tree/main/examples) for references on how to use this module.
