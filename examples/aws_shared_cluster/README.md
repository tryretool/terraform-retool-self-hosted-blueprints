# AWS — deploy into a shared / existing EKS cluster

Deploys Retool into a pre-existing EKS cluster (and VPC) rather than creating
one. It deploys only the Retool-specific pieces into dedicated, prefixed
namespaces and assumes the cluster already runs the common operators (External
Secrets Operator, cert-manager, the AWS Load Balancer Controller,
metrics-server).

Read [`guides/shared-clusters.md`](../../guides/shared-clusters.md) first — it
explains the namespace model, the `enable_*` toggles, and how to grant the
platform's ESO access to Retool's secrets.

## Before you apply

1. Copy `provider.example.tf` and fill in your AWS profile/region.
2. In `main.tf`, set the `locals` for your existing infrastructure:
   - `cluster_name`, `vpc_id`, `node_security_group_id`
   - `private_subnet_ids` (for RDS), `public_subnet_ids` (for the user ALB)
   - `domain_name`
3. Grant the platform's External Secrets Operator read access to Retool's
   secrets by attaching `module.retool-services.outputs.eso_irsa_role_arn` to its
   service account.

This example creates a managed RDS database. If you also bring your own
database, drop the `db-main` module and pass your connection details directly.
