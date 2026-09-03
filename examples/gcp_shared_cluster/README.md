# GCP — two Retool instances in one GKE cluster

A worked example of the pattern described in
**[`guides/shared-clusters.md`](../../guides/shared-clusters.md)** — read that
first. It explains which modules are shared, which are per-instance, and why.
This example is that guidance written out for GCP.

It stands up one VPC and one GKE cluster, then deploys two independent Retool
instances into them — `myretool-dev` and `myretool-prod`, each with its own
prefix, database, namespace and domain.

| File | Contents |
|---|---|
| `shared.tf` | the VPC and the cluster, instantiated once |
| `myretool-dev.tf` | everything belonging to the dev instance |
| `myretool-prod.tf` | everything belonging to the prod instance |

Adding a third instance means copying `myretool-prod.tf` and changing the prefix
and domain. `shared.tf` does not change.

## Before you apply

1. Copy `provider.example.tf` and fill in your project/region.
2. In `shared.tf`, set `prefix_global`, `project_id` and `region`.
3. In each `myretool-*.tf`, set `domain_name` and `license_key`.
4. Enable the required GCP APIs — see
   [`examples/gcp_all_inclusive`](../gcp_all_inclusive/README.md#required-gcp-apis).

Then the usual `terraform init` / `plan` / `apply`. Both instances come up in one
apply; nothing needs to be applied in stages.

## See also

- [Using a shared/existing Kubernetes cluster](../../guides/shared-clusters.md) —
  including how to deploy into a cluster you already run, and how to share one
  Postgres instance between Retool instances.
- [Upgrades](../../guides/upgrade-v0.md)
- [Troubleshooting](../../guides/troubleshooting.md)
- [Scaling](../../guides/scaling.md)
