## `azure-vnet` module

This is a Terraform module which provides the recommended networking and foundational infrastructure for production Retool deployments on Azure.

* Creates a VNet with configurable CIDR block
* Creates dedicated subnets for AKS, PostgreSQL Flexible Server, and Application Gateway
* Creates Network Security Groups with appropriate rules for each subnet
* Creates a NAT Gateway for AKS egress traffic
* Creates an Azure Key Vault for centralized secret storage

> [!NOTE] This module is designed to be used in conjunction with the other Azure-specific modules in [`retool-self-hosted-blueprints`](https://github.com/tryretool/retool-self-hosted-blueprints). See the [usage examples](https://github.com/tryretool/retool-self-hosted-blueprints/tree/main/examples) for references on how to use this module.
