## `azure-database` module

This is a Terraform module which provisions an Azure Database for PostgreSQL Flexible Server with defaults tuned for production Retool self-hosted deployments.

* Creates a PostgreSQL Flexible Server with VNet integration via a delegated subnet
* Creates a Private DNS Zone for private name resolution within the VNet
* Generates a random database password and stores it in Azure Key Vault
* Enables the UUID-OSSP and VECTOR extensions required by Retool

> [!NOTE] This module is intended to be used in conjunction with the other Azure-specific modules in [`retool-self-hosted-blueprints`](https://github.com/tryretool/retool-self-hosted-blueprints). See the [usage examples](https://github.com/tryretool/retool-self-hosted-blueprints/tree/main/examples) for references on how to use this module.
