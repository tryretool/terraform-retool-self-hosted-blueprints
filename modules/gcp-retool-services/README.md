## `gcp-retool-services` module

This is a Terraform module which provides extensions to a GKE cluster and supporting services recommended for running Retool self-hosted.

* Installs [External Secrets Operator](https://external-secrets.io/latest/) with Workload Identity for GCP Secret Manager access
* Installs [Reloader](https://github.com/stakater/Reloader) for automatic pod restarts on secret changes
* Creates ESO `ExternalSecret` resources for required Retool secrets so GCP Secret Manager remains the source of truth

> [!NOTE] This module is intended to be used in conjunction with the other GCP-specific modules in [`retool-self-hosted-blueprints`](https://github.com/tryretool/retool-self-hosted-blueprints). See the [usage examples](https://github.com/tryretool/retool-self-hosted-blueprints/tree/main/examples) for references on how to use this module.
