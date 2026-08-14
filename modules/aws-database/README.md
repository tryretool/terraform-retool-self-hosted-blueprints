## `aws-database` module

This is a Terraform module wrapper around the existing [AWS RDS Terraform module](https://registry.terraform.io/modules/terraform-aws-modules/rds/aws/latest), but with defaults and options tuned for production Retool self-hosted deployments.

### Adopting an existing database

A database created by other tooling — a CloudFormation stack, say — can be
imported into this module, but three of its defaults will otherwise rewrite the
database out from under whatever is still using it. Each has an opt-out:

| Variable | Why it matters when importing |
| --- | --- |
| `manage_master_user_password` | Defaults to `true`, letting RDS own and rotate the password. Applied to an imported database whose password is managed elsewhere, RDS generates a **new** password — instantly locking out anything still reading the old credentials. Set `false`, and pass the existing secret's ARN as `master_user_secret_arn` so downstream modules still find the credentials. |
| `security_group_name` | A security group's name is fixed at creation, and this module normally appends a unique suffix. If the name doesn't match the imported group's, Terraform destroys and recreates it — **taking every rule on it**. Set it to the existing name. |
| `db_subnet_group_name` | Same story: the name is fixed at creation, so an imported subnet group must be named exactly. |

Two more control what Terraform touches once the database is adopted:

- `manage_security_group_rules = false` leaves the imported group's existing rules
  alone. Terraform would otherwise delete every rule it doesn't know about and
  fail on the ones it would duplicate. You then declare the rules yourself —
  including ingress for the EKS nodes, which this module normally adds.
- `create_db_parameter_group = false` (with `parameter_group_name`) keeps the
  parameter group the database already uses, instead of attaching a fresh one.

See the [`aws_import_from_cloudformation`](../../examples/aws_import_from_cloudformation)
example for all of this wired together, including a helper that discovers the
values and performs the imports.

> [!NOTE] This module is intended to be used in conjunction with the other AWS-specific modules in [`retool-self-hosted-blueprints`](https://github.com/tryretool/retool-self-hosted-blueprints). See the [usage examples](https://github.com/tryretool/retool-self-hosted-blueprints/tree/main/examples) for references on how to use this module.
