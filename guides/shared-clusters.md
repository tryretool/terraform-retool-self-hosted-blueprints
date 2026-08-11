# Deploying into a shared / existing Kubernetes cluster

The `*_all_inclusive` examples stand up a dedicated cluster from scratch. This
guide covers deploying Retool into a cluster you do **not** exclusively own —
e.g. an existing EKS/GKE/AKS cluster shared with other workloads. All three
clouds support this.

Working starting points:
[`examples/aws_shared_cluster`](../examples/aws_shared_cluster),
[`examples/gcp_shared_cluster`](../examples/gcp_shared_cluster),
[`examples/azure_shared_cluster`](../examples/azure_shared_cluster).

The mechanics below use AWS resource names as the running example; the GCP and
Azure equivalents are noted where they differ.

## What changes in a shared cluster

### 1. Deliberate, prefixed namespaces

Everything is placed in dedicated namespaces instead of `default`:

| Namespace                  | Contents                                                                                                                                         |
|----------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------|
| `<prefix>-retool`          | the Retool Helm release, its ExternalSecrets, the namespaced ESO `SecretStore`, the RR credentials Secret, the user-ingress `TargetGroupBinding` |
| `<prefix>-retool-services` | the supporting operators this deployment owns (ESO, reloader, cert-manager, ALB controller, metrics-server)                                      |
| `kube-system`              | AWS Karpenter only (cluster-wide; from-scratch clusters only)                                                                                    |

Both namespaces are computed once inside `<cloud>-retool-services` and exported
as `retool_namespace` / `services_namespace`, so downstream modules
`retool-helm` and `aws-user-ingress` use the same namespaces without diverging
or duplicate config. 

If you want to deploy these workloads into existing namespaces, override
`retool_namespace` / `services_namespace` to target namespaces your platform
team pre-created, and set `create_namespaces = false` so Terraform doesn't try
to own them.

### 2. Disable the cluster-wide singletons you already run

A shared cluster usually already runs these. Each has an `enable_*` toggle on
`aws-retool-services` (all default `true`):

- `enable_external_secrets` — the External Secrets Operator
- `enable_cert_manager` — cert-manager (used by the ALB controller's webhook)
- `enable_alb_controller` — the AWS Load Balancer Controller
- `enable_metrics_server` — metrics-server
- `install_crds` — whether the bundled operators install their (cluster-scoped) CRDs

Turning `enable_external_secrets` off still creates the `SecretStore` and the
`ExternalSecret` resources — they are app config the platform's ESO reconciles.
You must grant that ESO read access to Retool's secrets: attach
`module.retool-services.outputs.eso_irsa_role_arn` to its service account (or
copy the equivalent policy onto whatever identity its controller uses).

On the cluster-creating side, `aws-eks` has `enable_karpenter` (default `true`);
disable it to bring your own node autoscaling (the controller node group is then
left untainted for general workloads).

### 3. Scoped operators and non-default ingress classes

- **reloader** is scoped to only watch `<prefix>-retool` (via a
  `namespaceSelector` on the namespace's `kubernetes.io/metadata.name` label),
  so it never restarts other namespaces' workloads.
- In AWS, The **ALB controller's IngressClass** is named `<prefix>-alb` and is **not**
  marked the cluster-default class. Set `make_default_ingress_class = true` only
  if you want this deployment to own the default IngressClass. (Retool routes via
  a `TargetGroupBinding` and does not need a default class.)

<!-- TODO: confirm the above?-->

## Pinning pods to node pools

A shared cluster often has dedicated node pools for different workloads,
labelled and/or tainted so only intended workloads land there. For Retool's pods
to schedule onto such a pool, they need a matching `nodeSelector` and/or
`tolerations`.

Every module that deploys pods via Helm — `*-retool-services`, `retool-helm`,
and `*-user-ingress` — exposes two variables for this:

- `pod_node_selector` (`map(string)`, default `{}`)
- `pod_tolerations` (list of Kubernetes toleration objects, default `[]`)

They apply to **every** pod the module's charts create. Set the same values on
each module you deploy so the whole stack lands on the pool:

```hcl
locals {
  # ...
  pod_node_selector = { "retool.com/pool" = "retool" }
  pod_tolerations = [{
    key      = "dedicated"
    operator = "Equal"
    value    = "retool"
    effect   = "NoSchedule"
  }]
}

module "retool-services" {
  # ...
  pod_node_selector = local.pod_node_selector
  pod_tolerations   = local.pod_tolerations
}

module "user-ingress" {
  # ...
  pod_node_selector = local.pod_node_selector
  pod_tolerations   = local.pod_tolerations
}

module "retool" {
  # ...
  pod_node_selector = local.pod_node_selector
  pod_tolerations   = local.pod_tolerations
}
```

Leave them unset (the default) to keep the charts' own defaults. Note that when
set, `pod_node_selector` replaces a chart's built-in `nodeSelector` default
where one exists (e.g. cert-manager defaults to `kubernetes.io/os: linux`);
include any such keys you still need in your map.

## Shared vs. per-instance Postgres database

When deploying multiple Retool instances into a single Kubernetes cluster, you
have the choice of sharing a single Postgres DB for all Retool instances, or
running a dedicated Postgres DB for each instance. The high level tradeoffs are
below.

| Factor                        | Shared DB                 | Per-instance DB                  |
|-------------------------------|---------------------------|----------------------------------|
| Cost                          | :white_check_mark: Lowest | :warning: Moderate–High          |
| Resource exhaustion tolerance | :warning: Lowest          | :white_check_mark: High          |
| Reliability                   | :warning: Lowest          | :white_check_mark: High          |
| Manual setup                  | :warning: Some required   | :white_check_mark: None required |

Besides the above tradeoffs, running multiple Retool instances off a single
Postgres DB instance is fully supported if adequately setup.

### Configuration for shared Postgres DB host

For the sake of illustration, say your goal is to create 2 separate Retool
instances, a "dev" and "prod" pair, and you want them to share a Kubernetes
cluster and a Postgres DB host to minimize costs.

To accomplish this, you'll need to follow these steps, explained in detail below:

1. Create 2 databases within your Postgres DB host, 1 for each Retool instance
2. Arrange your Terraform code so that each Retool instance uses the same
   Postgres host and connection credentials but only uses its corresponding
   database within the host.

#### 1. Creating per-instance databases inside the Postgres DB instance
<!-- TODO: separate guide for getting a psql shell -->

```sql
CREATE DATABASE "retool-acme-dev";
CREATE DATABASE "retool-acme-prod";
```

#### 1. Duplicating Retool instances to share a Postgres host

The `<cloud>-retool-services` and `retool-helm` modules usually expect an input
variable like `db = module.db-main.outputs`. This `db` input contains structured
connection settings that tell the downstream `<cloud>-retool-services` and
`retool-helm` modules where to find and how to connect to their database.

In the case of multiple Retool instances sharing a single Postgres host, we need
to have each Retool instance use mostly the same shared connection settings
(i.e. host, port, username, password stored in the CSP's secure secret store),
but with an override for database name. We can accomplish that with a config
arranged like below.

```terraform
locals {
  # ...
  prefix_global = "acme"
  
  dev = {
    prefix = "acme-dev"
    db_outputs = merge(module.db-main.outputs, {
      name = "retool-${local.prefix_dev}"
    })
  }
  
  prod = {
    prefix = "acme-prod"
    db_outputs = merge(module.db-main.outputs, {
      name = "retool-${local.prefix_prod}"
    })
  }
}

module "db-main" {
  # ...
  prefix = prefix_global
}

# repeat this whole module for -dev and -prod both
module "retool-services-dev" {
  # ...
  prefix = local.dev.prefix
  db = local.dev.db_outputs
}

# repeat this whole module for -dev and -prod both
module "retool-dev" {
  # ...
  retool_services = module.retool-services-dev.outputs
  db = local.dev.db_outputs
}
```

> [!NOTE]  
> The above snippet does not show how your `<cloud>-vpc`/`<cloud>-vnet` module,
> your managed Kubernetes module, nor your `<cloud>-user-ingress` module should
> be configured with this setup. Your vpc/vnet module and Kubernetes modules
> would use the `local.prefix_global` shown here, like `db-main` does. Your
> `<cloud>-user-ingress` module would be duplicated for each Retool instance,
> like `retool-dev` shown here, and would use a per-instance domain name, but it
> does not need a `db` input.
