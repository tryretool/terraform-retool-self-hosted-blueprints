## `azure-retool-services` module

This is a Terraform module providing the per-deployment supporting services recommended for running Retool self-hosted in AKS. Everything it creates belongs to one Retool deployment, so it can be instantiated several times against a single cluster.

* Creates the `<prefix>-retool` namespace the deployment lives in, and exports its name so `retool-helm` and `azure-user-ingress` use the same one
* Provisions the Retool secrets in Azure Key Vault
* Creates the `<prefix>-eso-identity` managed identity with a Key Vault access policy, and the Kubernetes service account that the cluster's shared External Secrets Operator impersonates through workload identity federation
* Creates a namespaced ESO `SecretStore` and the `ExternalSecret` resources, so Key Vault remains the source of truth
* Optionally generates agent sandbox secrets (JWT keypair, encryption key, API secret, Postgres URL) stored in Key Vault and synced to K8s via ESO
* Optionally creates an Azure Storage Account and Blob container for Remote Repository storage

> [!NOTE] This module is intended to be used in conjunction with the other Azure-specific modules in [`retool-self-hosted-blueprints`](https://github.com/tryretool/retool-self-hosted-blueprints). See the [usage examples](https://github.com/tryretool/retool-self-hosted-blueprints/tree/main/examples) for references on how to use this module.
