# AWS — deploy into a shared / existing EKS cluster

Deploys Retool into a pre-existing EKS cluster (and VPC) rather than creating
one. It instantiates `aws-eks` with `existing_cluster`, which adopts the cluster
and installs only the cluster-wide operators Retool needs (External Secrets
Operator, cert-manager, the AWS Load Balancer Controller, reloader), and puts
the Retool deployment itself in a single `<prefix>-retool` namespace. Each
operator has an `enable_*` toggle — turn off whatever your platform team already
runs.

Read [`guides/shared-clusters.md`](../../guides/shared-clusters.md) first — it
explains the namespace model, why the operators are cluster singletons, and how
the External Secrets Operator reaches Retool's secrets.

## Cluster prerequisites

- EKS Pod Identity available on the cluster — the External Secrets Operator gets
  its credentials through it. `aws-eks` installs the addon for an adopted cluster
  unless you set `enable_pod_identity_agent = false`.
- An IAM OIDC provider for the cluster, which the ALB controller's IRSA role
  needs. EKS does not create one; pass `existing_cluster.oidc_provider_arn` if
  the lookup by issuer URL is ambiguous.
- The worker-node security group id, which is not discoverable from the cluster
  API and is required by the database and user-ingress modules.

## Before you apply

1. Copy `provider.example.tf` and fill in your AWS profile/region.
2. In `main.tf`, set the `locals` for your existing infrastructure:
   - `cluster_name`, `vpc_id`, `node_security_group_id`
   - `private_subnet_ids` (for RDS), `public_subnet_ids` (for the user ALB)
   - `domain_name`
3. Confirm no other Terraform state already owns the cluster-wide operators —
   only one may install them.
4. If your platform team runs the External Secrets Operator rather than this
   module, set `enable_external_secrets = false` on `aws-eks` and pass its
   controller's IAM role ARN as `eso_controller_role_arns` on `retool-services`,
   so it can assume `module.retool-services.outputs.eso_role_arn`.

This example creates a managed RDS database. If you also bring your own
database, drop the `db-main` module and pass your connection details directly.

## See also

- [Upgrades](../../guides/upgrade-v0.md) — migrating an existing deployment.
- [Troubleshooting](../../guides/troubleshooting.md)
- [Scaling](../../guides/scaling.md)
