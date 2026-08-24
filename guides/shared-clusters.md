# Deploying into a shared / existing Kubernetes cluster

The `*_all_inclusive` examples stand up a dedicated cluster from scratch. This
guide covers deploying Retool into a cluster you do **not** exclusively own —
e.g. an existing EKS/GKE/AKS cluster shared with other workloads. All three
clouds support this.

Working starting points:
[`examples/aws_shared_cluster`](../examples/aws_shared_cluster),
[`examples/gcp_shared_cluster`](../examples/gcp_shared_cluster),
[`examples/azure_shared_cluster`](../examples/azure_shared_cluster).

The mechanics are the same on all three clouds and the variable names are
common unless noted; where a cloud genuinely differs, it gets its own block.
`<cloud>` below stands for `aws`, `gcp` or `azure`, and the cluster module means
`aws-eks`, `gcp-gke` or `azure-aks`.

## What changes in a shared cluster

### 1. One namespace for the deployment, conventional ones for the operators

The Retool deployment gets a single dedicated namespace. The cluster-wide
operators keep their conventional namespaces, because there is only ever one of
each per cluster.

| Namespace | Contents |
|---|---|
| `<prefix>-retool` | the Retool Helm release, its ExternalSecrets, the namespaced ESO `SecretStore`, the RR credentials Secret, and whatever routes traffic to it |
| `external-secrets`, `cert-manager`, `reloader` | the cluster-wide operators — one copy per cluster, installed by the cluster module |
| `kube-system` | the cloud's own cluster addons |

`<cloud>-retool-services` computes `retool_namespace` once and exports it, so
`retool-helm` and `<cloud>-user-ingress` use the same namespace without
diverging or duplicating config.

To deploy into a namespace your platform team pre-created, override
`retool_namespace` and set `create_namespace = false` so Terraform doesn't try
to own it.

What lands in `<prefix>-retool` alongside Retool differs by cloud: on AWS a
`TargetGroupBinding`, on GCP a Gateway API `Gateway` plus its `HTTPRoute`, and on
Azure an `Ingress`, its `Certificate` and the AGIC instance that reconciles it.

### 2. The cluster-wide operators are singletons

Some operators cannot be deployed once per Retool instance. Each owns
cluster-scoped objects — CRDs, `ValidatingWebhookConfiguration`s and
`ClusterRole`s whose names are fixed by the chart — so a second release collides
with the first on every one of them. They are installed **once per cluster** by
the cluster module.

| Operator | AWS | GCP | Azure |
|---|---|---|---|
| External Secrets Operator | ✅ | ✅ | ✅ |
| reloader | ✅ | ✅ | ✅ |
| cert-manager | ✅ | — (Google Certificate Manager issues certs) | ✅ |
| AWS Load Balancer Controller | ✅ | — | — |

Not everything that looks like an operator is a singleton. `external-dns` on GCP
and AGIC on Azure own no CRDs and no fixed-name webhooks, so each Retool
deployment runs its own, scoped to its own DNS zone or IngressClass. They stay
in `<cloud>-user-ingress`.

To get the singletons onto a cluster you did not create, instantiate the cluster
module with `existing_cluster`. It creates no network, no node pools and no
cluster:

<details>
<summary>AWS</summary>

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
}
```
</details>

<details>
<summary>GCP</summary>

```hcl
module "gke" {
  source = "tryretool/self-hosted-blueprints/retool//modules/gcp-gke"

  prefix     = local.prefix
  project_id = local.project_id
  region     = local.region

  existing_cluster = {
    name     = "my-shared-gke"
    location = local.region
  }
}
```

The adopted cluster must have Workload Identity enabled, and the Gateway API
enabled if you use `gcp-user-ingress`. Both are checked at plan time.
</details>

<details>
<summary>Azure</summary>

```hcl
module "aks" {
  source = "tryretool/self-hosted-blueprints/retool//modules/azure-aks"

  prefix              = local.prefix
  resource_group_name = local.resource_group_name
  location            = local.location

  existing_cluster = {
    name = "my-shared-aks"
  }
}
```

The adopted cluster must have `oidc_issuer_enabled` and
`workload_identity_enabled` set — every identity Retool creates federates
against that issuer.
</details>

Every addon and chart the cluster module installs has an enable toggle,
all defaulting `true`, so a cluster that already runs one can be adopted without
a second copy fighting over it. Common to all three clouds:
`enable_external_secrets`, `enable_reloader`, `install_crds`. Then
`enable_cert_manager` on AWS and Azure; `enable_alb_controller`,
`enable_karpenter`, `enable_metrics_server`, `enable_ebs_csi_driver` and the four
core-addon toggles on AWS.

> [!IMPORTANT]
> **Exactly one Terraform state per cluster may own these.** For a second Retool
> deployment in the same cluster, do not instantiate the cluster module again —
> deploy only `<cloud>-retool-services`, `retool-helm` and
> `<cloud>-user-ingress` with a different prefix.

### 3. Secrets stay isolated per deployment

There is one External Secrets Operator for the whole cluster, but each Retool
deployment keeps its own cloud identity, so one deployment can never read
another's secrets.

The shape is the same everywhere: `<cloud>-retool-services` creates a
per-deployment identity granted access to just that deployment's secrets, and
the deployment's namespaced `SecretStore` names it. The shared controller then
assumes that identity for that store rather than using its own. What differs is
the mechanism.

<details>
<summary>AWS — the store names an IAM role</summary>

`<prefix>-eso` is an IAM role scoped to this deployment's Secrets Manager paths.
Its trust policy admits the cluster ESO controller's role, and the `SecretStore`
sets `spec.provider.aws.role` to it.

If your platform team runs ESO, set `eso_controller_role_arns` on
`aws-retool-services` to the IAM role its controller pods use. Across accounts
that role also needs an identity policy allowing `sts:AssumeRole` on
`module.retool-services.outputs.eso_role_arn`; within one account the trust
policy alone is sufficient.

By default the controller may assume any role in the account whose name ends in
`-eso`. Override `external_secrets_assumable_role_arns` on `aws-eks` to narrow
that.
</details>

<details>
<summary>GCP — the store names a Kubernetes service account</summary>

`<prefix>-eso` is a Google service account holding
`roles/secretmanager.secretAccessor` on this deployment's secrets individually —
no project-level grant. A Kubernetes service account `retool-eso` in
`<prefix>-retool` is annotated with it and bound through Workload Identity, and
the `SecretStore` sets `spec.provider.gcpsm.auth.workloadIdentity.serviceAccountRef`
to that service account.

If your platform team runs ESO, bind its controller to
`module.retool-services.outputs.eso_gcp_service_account_email`, or copy the
per-secret IAM grants onto whatever identity it uses.
</details>

<details>
<summary>Azure — the store names a Kubernetes service account</summary>

`<prefix>-eso-identity` is a user-assigned managed identity with a Key Vault
access policy granting `Get`/`List`. A Kubernetes service account `retool-eso`
in `<prefix>-retool` carries its client ID, a federated credential trusts that
service account's subject, and the `SecretStore` sets
`spec.provider.azurekv.serviceAccountRef` to it.

If your platform team runs ESO, federate an additional credential on
`module.retool-services.outputs.eso_identity_client_id` for its controller's
service account, or grant its identity the same Key Vault access policy.
</details>

`create_external_secrets` on `<cloud>-retool-services` still controls whether the
`SecretStore` and `ExternalSecret` objects are created at all, independently of
who runs the operator.

### 4. Things that behave cluster-wide

**reloader** watches every namespace and, with `reloader_auto_reload_all`
(default `true`), restarts any workload whose referenced ConfigMap or Secret
changes — not just Retool's. Set it to `false` on the cluster module in a shared
cluster where that is unacceptable; Retool's own chart annotates its workloads
with `reloader.stakater.com/*`, so it keeps working either way.

Ingress differs enough per cloud to be worth stating separately.

<details>
<summary>AWS</summary>

The ALB controller's IngressClass is the chart default, `alb`, and is not marked
the cluster-default class. Set `make_default_ingress_class = true` on `aws-eks`
only if you want it to be. Retool routes via a `TargetGroupBinding` and does not
need a default class.
</details>

<details>
<summary>GCP</summary>

There is no in-cluster ingress controller: the GKE Gateway controller runs in
the control plane. Each deployment gets its own `Gateway` in its own namespace,
and therefore its own load balancer and static IP.

`external-dns` runs per deployment, named `<prefix>-external-dns` so its
cluster-scoped RBAC does not collide, and confined to its own DNS zone
(`--zone-id-filter`) and namespace. Set `enable_external_dns = false` to publish
records yourself.
</details>

<details>
<summary>Azure</summary>

AGIC binds 1:1 to an Application Gateway, so each deployment runs its own,
released as `<prefix>-ingress-azure` and confined by `ingressClass`,
`ingressClassResource` and `watchNamespace` to its own class and namespace. Its
IngressClass defaults to `<prefix>-agic`; override with `ingress_class_name`, or
set `enable_agic = false` and point that variable at an ingress controller you
already run.

cert-manager is shared, but the certificate is not. Each deployment creates a
namespaced `Issuer` (`<prefix>-letsencrypt`) whose Azure DNS solver names its own
managed identity, and grants that identity DNS Zone Contributor on its own zone
only. Set `cluster_issuer_name` to consume a `ClusterIssuer` your platform
already runs instead.
</details>

## Pinning pods to node pools

A shared cluster often has dedicated node pools for different workloads,
labelled and/or tainted so only intended workloads land there. For Retool's pods
to schedule onto such a pool, they need a matching `nodeSelector` and/or
`tolerations`.

Every module that deploys pods via Helm exposes two variables for this: the
cluster module (`aws-eks` / `gcp-gke` / `azure-aks`, for the cluster-wide
operators), `retool-helm` (Retool itself), and `gcp-user-ingress` /
`azure-user-ingress` (external-dns and AGIC). `aws-user-ingress` deploys no pods
and has neither variable.

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
