## `gcp-vpc` module

This is a Terraform module wrapper around the [Google Network Terraform module](https://registry.terraform.io/modules/terraform-google-modules/network/google/latest), with defaults tuned for production Retool self-hosted deployments on GCP. Includes Cloud NAT for private node egress and Private Service Access for Cloud SQL.

> [!NOTE] This module is designed to be used in conjunction with the other GCP-specific modules in [`retool-self-hosted-blueprints`](https://github.com/tryretool/retool-self-hosted-blueprints). See the [usage examples](https://github.com/tryretool/retool-self-hosted-blueprints/tree/main/examples) for references on how to use this module.
