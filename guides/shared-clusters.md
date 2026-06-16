# Deploying into a shared / existing Kubernetes cluster

The `*_all_inclusive` examples stand up a dedicated cluster from scratch. This
guide covers deploying Retool into a cluster you do **not** exclusively own —
e.g. an existing EKS cluster shared with other workloads. The AWS modules
support this today; GCP and Azure parity is planned.

See [`examples/aws_shared_cluster`](../examples/aws_shared_cluster) for a
working starting point.

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
