## `aws-vpc` module

This is a Terraform module wrapper around the existing [AWS VPC Terraform module](https://registry.terraform.io/modules/terraform-aws-modules/vpc/aws/latest), but with defaults and options tuned for production Retool self-hosted deployments.

> [!NOTE] This module is designed to be used in conjunction with the other AWS-specific modules in [`retool-self-hosted-blueprints`](https://github.com/tryretool/retool-self-hosted-blueprints). See the [usage examples](https://github.com/tryretool/retool-self-hosted-blueprints/tree/main/examples) for references on how to use this module.
