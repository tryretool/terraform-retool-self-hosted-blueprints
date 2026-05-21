## `azure-aks` module

This is a Terraform module which provisions an AKS (Azure Kubernetes Service) cluster with defaults tuned for production Retool self-hosted deployments.

* Creates an AKS cluster with system-assigned managed identity
* Configures Workload Identity (OIDC issuer) for secure pod-to-Azure-service authentication
* Uses standard Azure CNI networking for Application Gateway Ingress Controller compatibility
* Creates a Log Analytics workspace for cluster monitoring
* Configures an auto-scaling default node pool

> [!NOTE] This module is designed to be used in conjunction with the other Azure-specific modules in [`retool-self-hosted-blueprints`](https://github.com/tryretool/retool-self-hosted-blueprints). See the [usage examples](https://github.com/tryretool/retool-self-hosted-blueprints/tree/main/examples) for references on how to use this module.
