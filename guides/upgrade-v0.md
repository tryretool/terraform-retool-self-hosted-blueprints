# Upgrades 

## Unreleased

### Cluster-wide operators moved to the cluster module — all clouds

**Breaking on AWS, GCP and Azure:** 
* Some cluster operator singletons are moving from being managed by
  `<cloud>-retool-services` to the k8s cluster module, i.e.
  `aws-eks`/`gcp-gke`/`azure-aks`.
* The default Retool namespace is moving from `default` to `<prefix>-retool`.

On a deployment that was created on blueprints modules v0.4 or earlier, the above changes will **not** apply cleanly via Terraform unless you follow the below steps.

* Set `retool_namespace = "default"` and `create_namespace = false` on your `<cloud>-retool-services`
* Add some `moved {...}` blocks (below) to your Terraform stack.

Per-cloud detail follows. Read the section for the clouds you run.

### AWS - upgrade steps

First, remove the `vpc = ...` argument from your `aws-retool-services` module and add a namespace setting to avoid a namespace change.

```diff
 module "retool-services" {
   # ...
-  vpc    = module.vpc.outputs
 
+  # blueprints modules <=0.4 put Retool into `default` namespace always, so 
+  # specify this directly to avoid a whole recreate into a new 
+  # `${prefix}-retool` namespace.
+  retool_namespace = "default"
+  create_namespace = false
 }
```

Add these `moved` blocks to your **root** configuration, e.g. a local `moved.tf` file. They assume
your module calls are named `eks` and `retool-services`, as in the examples;
adjust if yours differ:

```hcl
moved {
  from = module.retool-services.helm_release.external_secrets
  to   = module.eks.helm_release.external_secrets[0]
}
moved {
  from = module.retool-services.helm_release.cert_manager
  to   = module.eks.helm_release.cert_manager[0]
}
moved {
  from = module.retool-services.helm_release.alb_controller
  to   = module.eks.helm_release.alb_controller[0]
}
moved {
  from = module.retool-services.helm_release.reloader
  to   = module.eks.helm_release.reloader[0]
}
moved {
  from = module.retool-services.module.alb_controller_irsa_role
  to   = module.eks.module.alb_controller_role[0]
}
moved {
  from = module.retool-services.aws_iam_policy.alb_controller_policy
  to   = module.eks.aws_iam_policy.alb_controller_policy[0]
}
moved {
  from = module.retool-services.aws_iam_role_policy_attachment.alb_controller_policy_attachment
  to   = module.eks.aws_iam_role_policy_attachment.alb_controller_policy_attachment[0]
}
moved {
  from = module.retool-services.aws_eks_pod_identity_association.eso
  to   = module.eks.aws_eks_pod_identity_association.external_secrets[0]
}
```

Then `terraform plan` and read it before applying. Expect:

* **in-place upgrades** for external-secrets, cert-manager and the ALB controller
* **replacement** of reloader, because its namespace changes from `default` to
  `reloader`. Terraform destroys before creating, and reloader's cluster-scoped
  RBAC is named after the release rather than the namespace, so it is deleted and
  recreated cleanly.
* **no CRD churn.** If the plan wants to destroy and recreate one of the first
  three, a `moved` block is missing or misspelled — fix that before applying,
  or you will hit the ownership error below.

#### AWS - upgrade troubleshooting

If an apply is performed without the above `moved` blocks for external-secrets,
Terraform destroys the old release and creates the new one with no dependency
between the two, so it may uninstall the old release *last* — and the ESO chart
templates its CRDs instead of shipping them in `crds/`, so that uninstall
deletes the cluster-scoped CRDs the new release just created, taking every
`SecretStore` and `ExternalSecret` with them. The symptom is an ESO pod logging
`CustomResourceDefinition ... "externalsecrets.external-secrets.io" not found`
while its Deployment looks healthy. `aws-eks` now stamps
`helm.sh/resource-policy: keep` on these CRDs so they survive any future
uninstall, but that only protects CRDs created by the new release — the ones
already in your cluster carry no such annotation.

If you have already hit this and the CRDs are gone, reinstall the release to
recreate them, then apply again so the `SecretStore` and `ExternalSecret`s are
recreated on top:

```
terraform apply -replace='module.eks.helm_release.external_secrets[0]'   # or module.gke / module.aks
terraform apply
```

Verify:

```
kubectl get crd | grep external-secrets.io
kubectl get externalsecrets -A
```

**The ESO bump needs one extra step.** The `SecretStore` and `ExternalSecret`
objects move from `external-secrets.io/v1beta1` to `/v1`, so Terraform deletes
the old objects and creates new ones — but chart 2.x stops serving `v1beta1`
(`crds.unsafeServeV1Beta1` defaults `false`), and if the chart upgrade lands
first those deletes fail with `no matches for kind ... in version
external-secrets.io/v1beta1`. Set `external_secrets_serve_v1beta1 = true` on
`aws-eks` for the apply that performs the upgrade, then remove it:

```hcl
module "eks" {
  # ...
  external_secrets_serve_v1beta1 = true # remove after the upgrade apply
}
```

The K8s Secrets themselves are untouched — the `ExternalSecret`s carry
`deletionPolicy: Retain`, so Retool keeps running on the already-synced values
while the objects are recreated.

Finally, if you created a `<prefix>-retool-services` namespace out of band, it is
now empty and can be removed:

```
kubectl delete namespace <prefix>-retool-services
```

#### AWS — Karpenter Pod Identity errors

You will likely also hit an error like `Error: creating EKS Pod Identity
Association`. To address, follow the troubleshooting guidance to
[re-import the existing association](./troubleshooting.md#fix--import-the-existing-association).

### GCP - upgrade steps

Only the External Secrets Operator and reloader move: GCP has no in-cluster
ingress controller (the GKE Gateway controller runs in the control plane) and no
cert-manager (TLS comes from Google Certificate Manager). `external-dns` stays
per-deployment — it owns no CRDs and no webhooks, so prefixing its release name
is enough for several to coexist.

First, add a namespace setting to your `retool-services` module to avoid a namespace change triggering a recreate.

```diff
 module "retool-services" {
   # ...

+  # blueprints modules <=0.4 put Retool into `default` namespace always, so 
+  # specify this directly to avoid a whole recreate into a new 
+  # `${prefix}-retool` namespace.
+  retool_namespace = "default"
+  create_namespace = false
 }
```

Add these `moved` blocks to a local `moved.tf` file.

```hcl
moved {
  from = module.retool-services.helm_release.external_secrets
  to   = module.gke.helm_release.external_secrets[0]
}
moved {
  from = module.retool-services.helm_release.reloader
  to   = module.gke.helm_release.reloader[0]
}
```

Both releases change namespace (from `<prefix>-retool-services` to
`external-secrets` and `reloader`), so Terraform replaces rather than upgrades
them. 

### Azure - upgrade steps

Upgrading a v0.4.x Azure deployment in place needs these two edits to your
root configuration:

```diff
 module "retool-services" {
   # ...

+  # blueprints modules <=0.4 put Retool into `default` namespace always, so 
+  # specify this directly to avoid a whole recreate into a new 
+  # `${prefix}-retool` namespace.
+  retool_namespace = "default"
+  create_namespace = false
 }

 module "user-ingress" {
   # ...

+  # New input. The retool namespace is now threaded from retool-services, so
+  # without it this module falls back to "<prefix>-retool" and puts the
+  # Certificate, Issuer and AGIC somewhere Retool isn't.
+  retool_services = module.retool-services.outputs
 }
```

Drop the two `retool-services` lines whenever you're ready to move Retool into
its own namespace — that is a one-time recreate of the Retool release.

You will also need to add the following `moved {...}` blocks to avoid helm errors during apply.

```hcl
moved {
  from = module.retool-services.helm_release.external_secrets
  to   = module.aks.helm_release.external_secrets[0]
}
moved {
  from = module.retool-services.helm_release.reloader
  to   = module.aks.helm_release.reloader[0]
}
moved {
  from = module.user-ingress.helm_release.cert_manager
  to   = module.aks.helm_release.cert_manager[0]
}
```

### If Helm refuses to adopt a resource — all clouds

Any time a release changes namespace — which is most of this upgrade on GCP and
Azure, and what skipping the `moved` blocks causes on AWS — the cluster-scoped
objects keep the old release's ownership annotations, and Helm refuses to adopt
them:

```
Error: Unable to continue with install: CustomResourceDefinition
"acraccesstokens.generators.external-secrets.io" in namespace "" exists and
cannot be imported into the current release: invalid ownership metadata
```

Helm's adoption check reads exactly three pieces of metadata: the
`meta.helm.sh/release-name` and `meta.helm.sh/release-namespace` annotations, and
the `app.kubernetes.io/managed-by=Helm` label. The script below rewrites those
three and nothing else, so no controller reconciles on it and no custom
resources are touched. Run it after the old releases are gone and before
applying the new ones. It defaults to a dry run.

```bash
#!/usr/bin/env bash
#
# adopt-helm-ownership.sh — re-stamp Helm release ownership on the cluster-scoped
# objects left behind by the old per-deployment operator releases, so the
# cluster-wide releases installed by aws-eks adopt them instead of failing.
#
#   ./adopt-helm-ownership.sh              # show what would change (AWS)
#   CLOUD=azure ./adopt-helm-ownership.sh  # ...on Azure
#   DRY_RUN=0 ./adopt-helm-ownership.sh    # actually change it
#
set -euo pipefail

KUBECTL="${KUBECTL:-kubectl}"
DRY_RUN="${DRY_RUN:-1}"

# Target coordinates — the namespaces and release names the cluster module
# installs. These are the same on all three clouds; CLOUD selects which extra
# per-cloud objects to sweep.
CLOUD="${CLOUD:-aws}"   # aws | gcp | azure
ESO_RELEASE="${ESO_RELEASE:-external-secrets}"
ESO_NAMESPACE="${ESO_NAMESPACE:-external-secrets}"
CERT_MANAGER_RELEASE="${CERT_MANAGER_RELEASE:-cert-manager}"
CERT_MANAGER_NAMESPACE="${CERT_MANAGER_NAMESPACE:-cert-manager}"
RELOADER_RELEASE="${RELOADER_RELEASE:-reloader}"
RELOADER_NAMESPACE="${RELOADER_NAMESPACE:-reloader}"
# AWS only.
ALB_RELEASE="${ALB_RELEASE:-alb-controller}"
ALB_NAMESPACE="${ALB_NAMESPACE:-alb-controller}"

# Match CRDs by API group rather than by name pattern, so unrelated CRDs (e.g.
# the VPC CNI's vpcresources.k8s.aws) are never touched.
crds_in_group() {
  "$KUBECTL" get crd \
    -o jsonpath="{range .items[?(@.spec.group==\"$1\")]}crd/{.metadata.name}{\"\n\"}{end}"
}

restamp() {
  local release="$1" namespace="$2" ref current
  shift 2
  for ref in "$@"; do
    [ -n "$ref" ] || continue
    if ! "$KUBECTL" get "$ref" >/dev/null 2>&1; then
      printf 'skip   %-64s (not present)\n' "$ref"
      continue
    fi
    current=$("$KUBECTL" get "$ref" -o jsonpath='{.metadata.annotations.meta\.helm\.sh/release-name}/{.metadata.annotations.meta\.helm\.sh/release-namespace}')
    if [ "$current" = "${release}/${namespace}" ]; then
      printf 'ok     %-64s already %s\n' "$ref" "$current"
      continue
    fi
    printf 'adopt  %-64s %s -> %s\n' "$ref" "${current:-<unowned>}" "${release}/${namespace}"
    [ "$DRY_RUN" = "0" ] || continue
    "$KUBECTL" annotate --overwrite "$ref" \
      "meta.helm.sh/release-name=${release}" \
      "meta.helm.sh/release-namespace=${namespace}" >/dev/null
    "$KUBECTL" label --overwrite "$ref" \
      "app.kubernetes.io/managed-by=Helm" >/dev/null
  done
}

# shellcheck disable=SC2046  # word splitting of the crd lists is intended

echo "== External Secrets Operator -> ${ESO_RELEASE}/${ESO_NAMESPACE}"
restamp "$ESO_RELEASE" "$ESO_NAMESPACE" \
  $(crds_in_group external-secrets.io) \
  $(crds_in_group generators.external-secrets.io) \
  validatingwebhookconfiguration/secretstore-validate \
  validatingwebhookconfiguration/externalsecret-validate

# GCP has no cert-manager: TLS comes from Google Certificate Manager.
if [ "$CLOUD" != "gcp" ]; then
  echo "== cert-manager -> ${CERT_MANAGER_RELEASE}/${CERT_MANAGER_NAMESPACE}"
  restamp "$CERT_MANAGER_RELEASE" "$CERT_MANAGER_NAMESPACE" \
    $(crds_in_group cert-manager.io) \
    $(crds_in_group acme.cert-manager.io) \
    mutatingwebhookconfiguration/cert-manager-webhook \
    validatingwebhookconfiguration/cert-manager-webhook
fi

if [ "$CLOUD" = "aws" ]; then
  echo "== AWS Load Balancer Controller -> ${ALB_RELEASE}/${ALB_NAMESPACE}"
  restamp "$ALB_RELEASE" "$ALB_NAMESPACE" \
    $(crds_in_group elbv2.k8s.aws) \
    mutatingwebhookconfiguration/alb-controller-webhook \
    validatingwebhookconfiguration/alb-controller-webhook \
    ingressclass/alb
fi

echo "== reloader -> ${RELOADER_RELEASE}/${RELOADER_NAMESPACE}"
restamp "$RELOADER_RELEASE" "$RELOADER_NAMESPACE" \
  clusterrole/reloader-reloader-role \
  clusterrolebinding/reloader-reloader-role-binding

echo
echo "Done."
```

Most lines will print `skip (not present)` — that is expected. If Helm still
refuses afterwards, the object it names is one the script does not know about:
find its current owner with `kubectl get <kind> <name> -o yaml`, add it to the
matching `restamp` call, or fall back to
[deleting it](./troubleshooting.md#fix-2--delete-conflicting-resources-and-re-apply).
