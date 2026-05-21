## `gcp-database` module

This is a Terraform module wrapper around the [Google Cloud SQL PostgreSQL Terraform module](https://registry.terraform.io/modules/terraform-google-modules/sql-db/google/latest), with defaults tuned for production Retool self-hosted deployments. Stores the database password in GCP Secret Manager.

> [!NOTE] This module is designed to be used in conjunction with the other GCP-specific modules in [`retool-self-hosted-blueprints`](https://github.com/tryretool/retool-self-hosted-blueprints). See the [usage examples](https://github.com/tryretool/retool-self-hosted-blueprints/tree/main/examples) for references on how to use this module.
