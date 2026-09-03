# Troubleshooting

Fixes for errors you may hit applying these modules. See also
[deploying into a shared/existing cluster](./shared-clusters.md) for the
namespace and operator model, and [upgrades](./upgrade-v0.md) for the
version-to-version migration steps, including CRD ownership.

## AWS only — S3 bucket name already taken (`BucketAlreadyExists`)

### Symptom

`terraform apply` fails creating the Remote Repository S3 bucket:

```
Error: creating S3 Bucket (retool-<prefix>-rr): operation error S3: CreateBucket,
https response error StatusCode: 409, ... BucketAlreadyExists: The requested
bucket name is not available. The bucket namespace is shared by all users of the
system.

  with module.retool-services.aws_s3_bucket.rr[0],
```

### Cause

`aws-retool-services` names the RR bucket `retool-<prefix>-rr` by default, and S3
bucket names are **globally unique across all AWS accounts**. If that name is
already taken (by you in another account/region, or by anyone else), the create
fails.

### Fix

Set `rr_s3_bucket_name` on the `aws-retool-services` module to a unique name:

```hcl
module "retool-services" {
  # ...
  enable_rr_s3      = true
  rr_s3_bucket_name = "acme-retool-prod-rr" # globally unique
}
```

The bucket is referenced by resource attributes elsewhere (IAM policy, the
`rr-s3-credentials` Secret), so changing only this variable is sufficient.

> The same applies on the other clouds, whose bucket/account names are also
> globally unique: GCP `gcp-retool-services` exposes `rr_gcs_bucket_name` (GCS
> bucket), and Azure `azure-retool-services` exposes `rr_storage_account_name`
> (Storage account, 3-24 lowercase alphanumeric chars).

## All clouds — Helm install fails on existing resources (`exists and cannot be imported into the current release`)

### Symptom

`terraform apply` fails installing/upgrading a Helm release because a
cluster-scoped resource it wants to create already exists and is owned by a
release in a different namespace. Most commonly a CRD:

```
Error: Unable to continue with install: CustomResourceDefinition
"acraccesstokens.generators.external-secrets.io" in namespace "" exists and
cannot be imported into the current release: invalid ownership metadata;
annotation validation error: key "meta.helm.sh/release-namespace" must equal
"<prefix>-retool-services": current value is "external-secrets"
```

The same error shape applies to other cluster-scoped objects a chart owns —
`ClusterRole`, `ClusterRoleBinding` (and, when their name/namespace shifts,
namespaced `Role`/`RoleBinding`):

```
Error: rendered manifests contain a resource that already exists. Unable to
continue with install: ClusterRole "external-secrets-..." ... exists and cannot
be imported into the current release ... key "meta.helm.sh/release-namespace"
must equal "<prefix>-retool-services": current value is "external-secrets"
```

### Cause

The various `helm_release` resources used in `retool-helm`, `<cloud>-retool-services`, and `<cloud>-user-ingress` all use Helm to deploy Kubernetes resources. Helm releases are tied to a namespace, so a namespace change causes the release to be recreated in the new namespace. The cluster-scoped resources previously deployed (CRDs especially — these carry
`helm.sh/resource-policy: keep`, so they survive uninstalls) still bear the
**old** release's `meta.helm.sh/release-namespace` annotation. Helm refuses to
adopt a resource owned by another release.

### Fix 1 — re-stamp the ownership metadata (preferred)

Helm's adoption check reads exactly three pieces of metadata: the
`meta.helm.sh/release-name` and `meta.helm.sh/release-namespace` annotations, and
the `app.kubernetes.io/managed-by=Helm` label. Rewriting those in place makes
Helm adopt the existing object instead of refusing it — nothing is deleted, no
custom resources are lost, and no controller reconciles on the change.

The upgrade guide ships a script that does this for the operators these modules
install: see [re-stamp Helm ownership](./upgrade-v0.md#if-helm-refuses-to-adopt-a-resource).
For a one-off object:

```sh
kubectl annotate --overwrite <kind> <name> \
  meta.helm.sh/release-name=<new-release> \
  meta.helm.sh/release-namespace=<new-namespace>
kubectl label --overwrite <kind> <name> app.kubernetes.io/managed-by=Helm
```

Then re-run `terraform apply`.

### Fix 2 — delete conflicting resources and re-apply

The simplest fix is to delete the resources named in the error and let the next
apply recreate them under the new release:

```sh
# CRDs (cluster-scoped; namespace is "")
kubectl delete crd acraccesstokens.generators.external-secrets.io

# ClusterRole / ClusterRoleBinding
kubectl delete clusterrole <name>
kubectl delete clusterrolebinding <name>

# A namespaced Role/RoleBinding in the OLD namespace
kubectl delete role <name> -n <old-namespace>
```

Then re-run `terraform apply`; Helm recreates each resource owned by the new
release.

> **Deleting a CRD also deletes every custom resource of that kind**
> (`SecretStore`, `ExternalSecret`, `Certificate`, etc.), which interrupts the
> reconciliation those objects drive — e.g. the K8s Secrets ESO syncs may briefly
> disappear and be recreated, and pods that mount them can restart. Treat this as
> potentially disruptive: **do it during off-hours / a maintenance window**, and
> expect the controllers to re-reconcile everything once the apply completes.

Prefer Fix 1 above where you can: re-stamping avoids the momentary loss of the
custom resources entirely.

### Fix 3 — pin to the old namespace

If you'd rather not move the Retool deployment's namespace at all (no deletes,
no downtime), keep it where it already lives. `<cloud>-retool-services` is the
single source of truth for it — it exposes `retool_namespace`, and the
`retool-helm` and `<cloud>-user-ingress` modules consume that name from its
outputs. Set it to the namespace your existing release already occupies and the
Retool Helm release is upgraded in place rather than recreated.

Set it on `<cloud>-retool-services`:

```hcl
module "retool-services" {
  # ...

  # Pin to the namespace the existing deployment already uses instead of the
  # "<prefix>-retool" default.
  retool_namespace = "default"

  # If that namespace already exists (created out of band or by a prior apply),
  # don't try to create/own it here.
  create_namespace = false
}
```

The cluster-wide operators are not pinnable this way: they are singletons
installed once per cluster by the cluster module (`aws-eks` / `gcp-gke` /
`azure-aks`) in their own conventional namespaces.

`retool-helm` and `<cloud>-user-ingress` pick the namespace up automatically from
the retool-services outputs — no per-module change needed when they're wired the
standard way:

```hcl
module "retool" {
  # ...
  retool_services = module.retool-services.outputs
}
```
