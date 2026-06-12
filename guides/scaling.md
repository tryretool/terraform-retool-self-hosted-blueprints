# Scaling a self-hosted Retool deployment

This guide covers the two levers that matter most for capacity: **the database**
and **the Retool services**. It applies to all clouds; the variable names below
are the same across the AWS, GCP, and Azure modules unless noted.

## TL;DR

- Scale **services** by passing standard Retool Helm values
  (`replicaCount`, `resources`) through `retool_helm_extra_values`.
- Scale the **database** with the `tier`/`sku_name` and `max_connections`
  inputs on the database module.
- The most common early symptom of an undersized deployment is backends
  flapping between healthy/unhealthy because the database is **out of
  connections** — see [Database connections](#database-connections).

## Scaling the Retool services

The `retool-helm` module forwards `retool_helm_extra_values` verbatim to the
Retool chart, so anything in the
[chart's `values.yaml`](https://github.com/tryretool/retool-helm/blob/main/charts/retool/values.yaml)
is available. Use plain integer replica counts and Kubernetes resource requests
to size each service independently:

```hcl
module "retool" {
  source = "tryretool/self-hosted-blueprints/retool//modules/retool-helm"
  # ...

  retool_helm_extra_values = [
    yamlencode({
      # Main web/backend service
      replicaCount = 3
      resources = {
        requests = { cpu = "1", memory = "2Gi" }
        limits   = { memory = "4Gi" }
      }

      # Workflows service (when workflows_enabled = true)
      workflows = {
        replicaCount = 2
        resources = {
          requests = { cpu = "1", memory = "2Gi" }
        }
      }
    })
  ]
}
```

Start by scaling **replica counts** horizontally for throughput, and raise
**resource requests/limits** if individual pods are CPU/memory constrained.
Apply changes incrementally and watch pod health (`kubectl get pods`) and
database connection usage after each change.

> [!NOTE]
> We intentionally expose the raw Helm knobs (integers) rather than opinionated
> "S/M/L/XL" presets — sizing depends heavily on your workload, and a preset
> that isn't matched to a real capacity profile tends to mislead more than it
> helps.

## Scaling the database

### Instance size

Pick the managed-Postgres machine size with the database module's size input:

| Cloud | Variable | Example |
|-------|----------|---------|
| AWS   | `instance_class` | `db.r6g.large` |
| GCP   | `tier`           | `db-custom-2-7680` |
| Azure | `sku_name`       | `GP_Standard_D2s_v3` |

For production also consider cross-zone high availability (`availability_type =
"REGIONAL"` on GCP, `multi_az` on AWS, `high_availability_mode` on Azure).

### Database connections

The full stack (main + workflows + agent sandbox) opens a lot of Postgres
connections. Small default instance tiers ship with a low `max_connections`,
which causes backends to **start, exhaust connections, and crash-loop** — they
appear to flap between healthy and unhealthy.

How you raise the connection ceiling depends on the cloud:

- **GCP** — set the `max_connections` shorthand on the `gcp-database` module:

  ```hcl
  module "db-main" {
    source          = "tryretool/self-hosted-blueprints/retool//modules/gcp-database"
    tier            = "db-g1-small"
    max_connections = 300
  }
  ```

  The all-inclusive GCP examples set `max_connections = 300` for this reason.

- **AWS** — add a `max_connections` entry to the RDS parameter group via the
  `parameters` input on the `aws-database` module:

  ```hcl
  parameters = [{ name = "max_connections", value = "300" }]
  ```

  (RDS's default `max_connections` scales with instance memory, so larger
  `instance_class` values raise it automatically.)

- **Azure** — Flexible Server derives `max_connections` from the `sku_name`;
  move to a larger SKU to get more connections.

If you scale service replica counts up, scale the connection ceiling (and likely
the instance size) along with them.
