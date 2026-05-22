## `azure-retool-services` module

This is a Terraform module which provides Kubernetes add-ons and supporting services recommended for running Retool self-hosted in AKS.

* Installs [External Secrets Operator](https://external-secrets.io/latest/) with Azure Key Vault as the backend
  * Includes a ClusterSecretStore and Workload Identity federation for secure Key Vault access
* Installs [Reloader](https://github.com/stakater/Reloader) for automatic pod restarts on Secret/ConfigMap changes
* Installs ESO `ExternalSecret` resources for required Retool secrets so Azure Key Vault remains the source of truth
* Optionally generates agent sandbox secrets (JWT keypair, encryption key, API secret, Postgres URL) stored in Key Vault and synced to K8s via ESO
* Optionally creates an Azure Storage Account and Blob container for Remote Repository storage

> [!NOTE] This module is intended to be used in conjunction with the other Azure-specific modules in [`retool-self-hosted-blueprints`](https://github.com/tryretool/retool-self-hosted-blueprints). See the [usage examples](https://github.com/tryretool/retool-self-hosted-blueprints/tree/main/examples) for references on how to use this module.
