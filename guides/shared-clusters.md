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

| Namespace | Contents |
|---|---|
| `<prefix>-retool` | the Retool Helm release, its ExternalSecrets, the namespaced ESO `SecretStore`, the RR credentials Secret, the user-ingress `TargetGroupBinding` |
| `<prefix>-retool-services` | the supporting operators this deployment owns (ESO, reloader, cert-manager, ALB controller, metrics-server) |
| `kube-system` | Karpenter only (cluster-wide; from-scratch clusters only) |

Both namespaces are computed once inside `aws-retool-services` and exported as
`retool_namespace` / `services_namespace`, so `retool-helm` and
`aws-user-ingress` consume the same values. Override `retool_namespace` /
`services_namespace` to target namespaces your platform team pre-created, and
set `create_namespaces = false` so Terraform doesn't try to own them.

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
  `namespaceSelector` on the namespace's `kubernetes.io/metadata.name` label), so
  it never restarts other tenants' workloads.
- The **ALB controller's IngressClass** is named `<prefix>-alb` and is **not**
  marked the cluster-default class. Set `make_default_ingress_class = true` only
  if you want this deployment to own the default IngressClass. (Retool routes via
  a `TargetGroupBinding` and does not need a default class.)

## Per-cloud differences

The namespace model, `create_namespaces`, and the namespaced ESO `SecretStore`
(named `retool-secretstore`, in the retool namespace) are identical across
clouds. Cloud-specific points:

- **AWS** — operators (ESO, cert-manager, ALB controller, metrics-server) live in
  `aws-retool-services`. Toggles: `enable_external_secrets`, `enable_reloader`,
  `enable_cert_manager`, `enable_alb_controller`, `enable_metrics_server`,
  `install_crds`, `make_default_ingress_class`. `aws-eks` adds `enable_karpenter`.
  ESO uses controller-based auth (Pod Identity); in shared mode attach
  `eso_irsa_role_arn` to the platform ESO.
- **GCP** — `gcp-retool-services` runs ESO + reloader (`enable_external_secrets`,
  `enable_reloader`, `install_crds`); `gcp-user-ingress` runs external-dns
  (`enable_external_dns`), already scoped to the retool namespace and using a
  per-deployment `txtOwnerId`. The Gateway/HTTPRoute live in the retool
  namespace. ESO uses the controller's Workload Identity; in shared mode bind the
  platform ESO to `eso_gcp_service_account_email`.
- **Azure** — `azure-retool-services` runs ESO + reloader; `azure-user-ingress`
  runs cert-manager + AGIC. Toggles: `enable_external_secrets`, `enable_reloader`,
  `enable_cert_manager`, `enable_agic`, `install_crds`, plus `ingress_class_name`
  and `cluster_issuer_name` to target an existing ingress controller / ClusterIssuer.
  ESO uses the controller's Workload Identity; in shared mode federate the
  platform ESO's service account to `eso_identity_client_id`. AGIC's own
  IngressClass name is fixed by its chart, so conflict avoidance in a shared
  cluster is via `enable_agic = false` (bring your own ingress) rather than
  renaming the class.

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

## Migrating an existing from-scratch deployment

The namespace is a force-new attribute on the Helm release and the
ExternalSecrets. Upgrading an existing `default`-namespace deployment to the new
prefixed defaults will **destroy and recreate** the Retool release and its
secrets (a brief outage, and any in-cluster-only state is lost).

To upgrade **in place with no churn**, pin the namespaces back to their previous
values and tell the module the namespaces already exist:

```hcl
module "retool-services" {
  # ...
  retool_namespace   = "default"
  services_namespace = "default" # operators previously lived in their own ns;
                                  # see below if you want to preserve those exactly
  create_namespaces  = false
}
```

Note the operators previously ran in distinct namespaces (`external-secrets`,
`cert-manager`, `alb-controller`) and metrics-server in `kube-system`. Helm
releases are namespace-scoped, so moving them is also a recreate. If you need a
zero-disruption upgrade of the operators too, plan the move during a maintenance
window, or keep the old layout by overriding `services_namespace` and accepting
that the operators consolidate into one namespace on next apply.

When you're ready to adopt the prefixed namespaces, do it as a deliberate
migration: drain/cordon as needed, apply, and re-point DNS once the new release
is healthy.

### Relocating CRD-installing charts (cert-manager, External Secrets Operator)

cert-manager and the External Secrets Operator install their CRDs with their
Helm release (`install_crds = true`), and those CRDs carry
`helm.sh/resource-policy: keep`. When the release moves namespaces, Helm
uninstalls the old release but **keeps the CRDs** — stamped with the old
release's ownership annotation. The relocated release then fails to install:

```
Error: Unable to continue with install: CustomResourceDefinition
"certificaterequests.cert-manager.io" ... cannot be imported into the current
release: invalid ownership metadata; annotation validation error: key
"meta.helm.sh/release-namespace" must equal "<prefix>-retool-services":
current value is "cert-manager"
```

The CRDs already exist cluster-wide, so resolve it one of two ways:

1. **Don't re-own the CRDs (simplest).** Set `install_crds = false` on the
   relocated module for the migration apply — the existing CRDs are left in
   place and the new release doesn't try to adopt them. cert-manager / ESO work
   fine against externally-managed CRDs.

   ```hcl
   module "retool-services" { # and azure user-ingress (cert-manager)
     # ...
     install_crds = false
   }
   ```

2. **Keep Helm managing them.** Re-stamp the retained CRDs' ownership annotation
   to the new namespace before re-applying, so the relocated release (with
   `install_crds = true`) can adopt them:

   ```sh
   # cert-manager
   kubectl annotate crd \
     certificaterequests.cert-manager.io certificates.cert-manager.io \
     challenges.acme.cert-manager.io clusterissuers.cert-manager.io \
     issuers.cert-manager.io orders.acme.cert-manager.io \
     meta.helm.sh/release-namespace=<prefix>-retool-services --overwrite

   # External Secrets Operator (if you hit the same error)
   kubectl annotate crd \
     $(kubectl get crd -o name | grep external-secrets.io) \
     meta.helm.sh/release-namespace=<prefix>-retool-services --overwrite
   ```

   (The release *name* is unchanged — `cert-manager` / `external-secrets` — so
   only `release-namespace` needs patching.)

This only affects in-place migrations; net-new deployments in the prefixed
layout create the CRDs owned by the relocated release from the start.
