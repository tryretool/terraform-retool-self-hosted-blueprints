# Scaling a self-hosted Retool deployment

This guide covers the two levers that matter most for capacity: **the database**
and **the Retool services**. It applies to all clouds; the variable names below
are the same across the AWS, GCP, and Azure modules unless noted.

## TL;DR

- Scale **services** by passing standard Retool Helm values
  (`replicaCount`, `resources`) through `retool_helm_extra_values`.
- Scale the **database** with the `tier`/`sku_name` and `max_connections`
  inputs on the database module.
- A common early symptom of an undersized deployment is backends flapping
  between healthy/unhealthy because the database is **out of connections** — see
  [Database connections](#database-connections).

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
        # The workflows backend only powers the workflows IDE and receives 
        # triggers, so it usually needs fewer replicas compared to the workflow 
        # workers.
        backend = {
          replicaCount = 1
        }
        # Workflows worker is what handles most workflow coordination and 
        # execution, so its replica count is often the first throughput bottleneck.
        worker = {
          replicaCount = 2
        }
        resources = {
          requests = { cpu = "1", memory = "2Gi" }
        }
      }

      # Code Executor service (when workflows_enabled = true)
      codeExecutor = {
        # The code executor runs any custom code blocks (JS, Python) that are 
        # part of a workflow. It becomes a bottleneck when custom code blocks 
        # are either run very frequently or individually do lots of work.
        # For high frequency, scale replicaCount first. If heavy code blocks are
        # individualy hitting limits (i.e. timing out, hitting resource errors),
        # increase resource requests/limits.
        replicaCount = 2
        resources = {
          requests = { cpu = "1", memory = "1Gi" }
          limits   = { cpu = "2", memory = "2Gi" }
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

## Scaling the database

### Instance size

Pick the managed-Postgres machine size with the database module's size input.
For production also enable cross-zone high availability.

<details>
<summary>AWS</summary>

```hcl
module "db-main" {
  # ...

  # see https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/Concepts.DBInstanceClass.Summary.html
  instance_class = "db.r6g.large"
  multi_az       = true
}
```

</details>

<details>
<summary>GCP</summary>

```hcl
module "db-main" {
  # ...

  # see https://cloud.google.com/sql/docs/postgres/instance-settings#machine-type-2ndgen
  tier = "db-custom-2-7680"
  # cross-zone HA with automatic failover (GCP equivalent of AWS multi_az)
  availability_type = "REGIONAL"
}
```

</details>

<details>
<summary>Azure</summary>

```hcl
module "db-main" {
  # ...

  # see https://learn.microsoft.com/azure/postgresql/flexible-server/concepts-compute
  sku_name               = "GP_Standard_D2s_v3"
  high_availability_mode = "ZoneRedundant"
}
```

</details>

### Database connections

The full stack (main + workflows + agent sandbox) can use many Postgres
connections. Small default instance tiers ship with a low `max_connections`,
which causes backends to **start, exhaust connections, and crash-loop** — they
appear to flap between healthy and unhealthy.

How you raise the connection ceiling depends on the cloud. If you scale service
replica counts up, scale the connection ceiling (and likely the instance size)
along with them.

<details>
<summary>AWS</summary>

RDS's default `max_connections` scales with instance memory, so a larger
`instance_class` raises it automatically. To set it explicitly, add a
`max_connections` entry to the RDS parameter group via the `parameters` input:

```hcl
module "db-main" {
  # ...

  parameters = [{ name = "max_connections", value = "300" }]
}
```

</details>

<details>
<summary>GCP</summary>

Set the `max_connections` shorthand on the module (the all-inclusive GCP
examples set `300` for this reason):

```hcl
module "db-main" {
  # ...

  tier            = "db-g1-small"
  max_connections = 300
}
```

</details>

<details>
<summary>Azure</summary>

Flexible Server derives `max_connections` from the `sku_name` — move to a larger
SKU to get more connections:

```hcl
module "db-main" {
  # ...

  # see https://learn.microsoft.com/azure/postgresql/flexible-server/concepts-limits#maximum-connections
  sku_name = "GP_Standard_D2s_v3"
}
```

</details>
