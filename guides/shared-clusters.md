# Deploying into a shared / existing Kubernetes cluster

The `*_all_inclusive` examples stand up a dedicated cluster from scratch. This
guide covers deploying Retool into a cluster you do **not** exclusively own —
e.g. an existing EKS/GKE/AKS cluster shared with other workloads. All three
clouds support this.

Working starting points:
[`examples/aws_shared_cluster`](../examples/aws_shared_cluster),
[`examples/gcp_shared_cluster`](../examples/gcp_shared_cluster),
[`examples/azure_shared_cluster`](../examples/azure_shared_cluster).

The mechanics below describe the AWS stack. GCP and Azure follow the same shape
but still deploy their supporting operators per-deployment into a
`<prefix>-retool-services` namespace, configured by `services_namespace`,
`create_namespaces` and the `enable_*` toggles on `<cloud>-retool-services`
rather than on the cluster module. Where this guide says `aws-eks` or
`create_namespace`, read the older equivalents for those clouds.

## What changes in a shared cluster

### 1. One namespace for the deployment, conventional ones for the operators

The Retool deployment gets a single dedicated namespace. The cluster-wide
operators keep their conventional namespaces, because there is only ever one of
each per cluster.

| Namespace                                                       | Contents                                                                                                                                     |
|-----------------------------------------------------------------|----------------------------------------------------------------------------------------------------------------------------------------------|
| `<prefix>-retool`                                                 | the Retool Helm release, its ExternalSecrets, the namespaced ESO `SecretStore`, the RR credentials Secret, the user-ingress `TargetGroupBinding` |
| `external-secrets`, `cert-manager`, `alb-controller`, `reloader` | the cluster-wide operators — one copy per cluster, installed by `aws-eks`                                                                     |
| `kube-system`                                                     | Karpenter and the EKS-managed cluster addons                                                                                                  |

`<cloud>-retool-services` computes `retool_namespace` once and exports it, so
`retool-helm` and `<cloud>-user-ingress` use the same namespace without
diverging or duplicating config.

To deploy into a namespace your platform team pre-created, override
`retool_namespace` and set `create_namespace = false` so Terraform doesn't try
to own it.

### 2. The cluster-wide operators are singletons, and live in `aws-eks`

The External Secrets Operator, cert-manager, the AWS Load Balancer Controller,
reloader, metrics-server and Karpenter cannot be deployed once per Retool
instance. Each owns cluster-scoped objects — CRDs, `ValidatingWebhookConfiguration`s
and `ClusterRole`s whose names are fixed by the chart — so a second release
collides with the first on every one of them. They are installed **once per
cluster** by `aws-eks`.

To get them onto a cluster you did not create, instantiate `aws-eks` with
`existing_cluster`. It creates no cluster, VPC or node groups:

```hcl
module "eks" {
  source = "tryretool/self-hosted-blueprints/retool//modules/aws-eks"

  prefix = local.prefix
  region = local.region

  existing_cluster = {
    name                   = "my-shared-eks"
    node_security_group_id = "sg-0123456789"
  }

  # Karpenter is wired to the controller node group this module creates
  # alongside a new cluster, so it cannot run against an adopted one.
  enable_karpenter = false

  # Turn off whatever the cluster already runs.
  enable_ebs_csi_driver   = false
  enable_metrics_server   = false
  enable_external_secrets = true
  enable_cert_manager     = true
  enable_alb_controller   = true
  enable_reloader         = true
}
```

Every addon and chart has an enable toggle (all default `true`), so a cluster
that already runs one can be adopted without a second copy fighting over it:
`enable_external_secrets`, `enable_cert_manager`, `enable_alb_controller`,
`enable_reloader`, `enable_metrics_server`, `enable_ebs_csi_driver`,
`enable_karpenter`, `enable_coredns_addon`, `enable_kube_proxy_addon`,
`enable_vpc_cni_addon`, `enable_pod_identity_agent`, and `install_crds` for the
CRDs the operators would otherwise install.

> [!IMPORTANT]
> **Exactly one Terraform state per cluster may own these.** For a second Retool
> deployment in the same cluster, do not instantiate `aws-eks` again — deploy
> only `<cloud>-retool-services`, `retool-helm` and `<cloud>-user-ingress` with a
> different prefix.

### 3. Secrets stay isolated per deployment

There is one External Secrets Operator for the whole cluster, but each Retool
deployment keeps its own IAM identity, so one deployment can never read
another's secrets.

`aws-retool-services` creates a `<prefix>-eso` role holding read access to just
that deployment's secrets, and trusts the cluster controller's role in its trust
policy. The deployment's namespaced `SecretStore` then names that role in
`spec.provider.aws.role`, so the controller assumes it — with its own pod
identity as the base credential — for that deployment's secrets only.

Two supported wirings:

1. **`aws-eks` installs the operator.** Pass `eks = module.eks.outputs` to
   `aws-retool-services`; the controller's role ARN flows through and everything
   is wired automatically.
2. **Your platform team runs the operator.** Set `enable_external_secrets = false`
   on `aws-eks` and set `eso_controller_role_arns` on `aws-retool-services` to
   the IAM role its controller pods use. If that operator runs in a *different*
   AWS account, its role also needs an identity policy allowing `sts:AssumeRole`
   on `module.retool-services.outputs.eso_role_arn` — within one account the
   trust policy alone is sufficient.

If neither is set, `terraform plan` fails with a message telling you so rather
than creating a role nothing can assume.

By default the controller is allowed to assume any role in the account whose
name ends in `-eso`, which is what `aws-retool-services` names them. Override
`external_secrets_assumable_role_arns` on `aws-eks` to narrow that, or to widen
it if you renamed the per-deployment roles.

`create_external_secrets` on `aws-retool-services` still controls whether the
`SecretStore` and `ExternalSecret` objects are created at all, independently of
who runs the operator.

### 4. Things that behave cluster-wide

- **reloader** watches every namespace and, with `reloader_auto_reload_all`
  (default `true`), restarts any workload whose referenced ConfigMap or Secret
  changes — not just Retool's. Set it to `false` in a shared cluster where that
  is unacceptable; Retool's own chart annotates its workloads with
  `reloader.stakater.com/*`, so it keeps working either way.
- **The ALB controller's IngressClass** is the chart default, `alb`, and is not
  marked the cluster-default class. Set `make_default_ingress_class = true` on
  `aws-eks` only if you want it to be. Retool routes via a `TargetGroupBinding`
  and does not need a default class.

## Pinning pods to node pools

A shared cluster often has dedicated node pools for different workloads,
labelled and/or tainted so only intended workloads land there. For Retool's pods
to schedule onto such a pool, they need a matching `nodeSelector` and/or
`tolerations`.

Every module that deploys pods via Helm exposes two variables for this — on AWS
that is `aws-eks` (the cluster-wide operators), `retool-helm` (Retool itself),
and on GCP/Azure the `*-retool-services` and `*-user-ingress` modules:

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

module "eks" {
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

Terraform cannot usually manage the data inside your Postgres instance, so you'll have to get a psql shell into your instance to manually create a database for each deployment sharing the instance.

If you have `kubectl` configured with a local kubeconfig profile to access your Kubernetes cluster, you can create a temporary pod with `psql` installed using the below command. This is often convenient, if possible, since your Postgres instance is usually not not accessible externally but is accessible to pods in your cluster.

```sh
kubectl run db-surgery-tmp --image=postgres:latest -it --rm --restart=Never -- sh
```

You'll need to plug in your Postgres host, admin user, and password in order for `psql` to successfully connect.

Once in a `psql` shell, you can create a database for each Retool deployment you wish to support like so.

```sql
CREATE DATABASE "retool-acme-dev";
CREATE DATABASE "retool-acme-prod";
```

#### 2. Duplicating Retool instances to share a Postgres host

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
      name = "retool-acme-dev"
    })
  }
  
  prod = {
    prefix = "acme-prod"
    db_outputs = merge(module.db-main.outputs, {
      name = "retool-acme-prod"
    })
  }
}

module "db-main" {
  # ...
  prefix = local.prefix_global
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
