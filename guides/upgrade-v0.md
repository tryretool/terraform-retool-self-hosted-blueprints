# Upgrades 

## Unreleased

### Cluster-wide operators moved from `aws-retool-services` to `aws-eks`

**Breaking.** The External Secrets Operator, cert-manager, the AWS Load Balancer
Controller and Stakater reloader are cluster singletons: each owns CRDs,
admission webhook configurations and/or ClusterRoles whose names are fixed by the
chart, so only one copy can exist per cluster and they cannot be installed once
per Retool deployment. They now install from `aws-eks`, alongside Karpenter, the
EBS CSI driver and metrics-server. `aws-retool-services` keeps only what is
genuinely per-deployment.

Each chart keeps the namespace and release name it already used, except reloader,
which moves from `default` to its own `reloader` namespace.

To install the operators onto a cluster this module did not create, instantiate
`aws-eks` with the new `existing_cluster` input — it creates no cluster, VPC or
node groups:

```hcl
module "eks" {
  source = "tryretool/self-hosted-blueprints/retool//modules/aws-eks"

  prefix = local.prefix
  region = local.region

  existing_cluster = {
    name                   = "my-shared-eks"
    node_security_group_id = "sg-0123456789"
  }

  enable_karpenter = false
}
```

Every addon and chart now has an enable toggle so an existing cluster can be
adopted without a second copy of anything: `enable_external_secrets`,
`enable_cert_manager`, `enable_alb_controller`, `enable_reloader`,
`enable_metrics_server`, `enable_ebs_csi_driver`, `enable_karpenter`,
`enable_coredns_addon`, `enable_kube_proxy_addon`, `enable_vpc_cni_addon`,
`enable_pod_identity_agent`. All default `true`.

`enable_karpenter` must be `false` when `existing_cluster` is set — Karpenter's
IAM is wired to the controller node group `aws-eks` only creates alongside a new
cluster. Terraform fails at plan with that message rather than at apply.

#### Config changes you must make by hand

Terraform reports most of these as `Unsupported argument` / `Unsupported
attribute`; it cannot fix them for you.

On `aws-retool-services`:

| Change                                                                     | What to do                                                                      |
|------------------------------------------------------------------------------|-----------------------------------------------------------------------------------|
| `vpc` removed                                                                | Delete the argument — only the ALB controller used it, and it moved to `aws-eks`. |
| `eks` narrowed to `{ eso_controller_role_arn }`                              | Keep passing `eks = module.eks.outputs`; extra attributes are dropped. If you hand-built the object, replace it.                             |
| `enable_metrics_server` removed                                              | Move it to your `aws-eks` block (see the metrics-server section below).           |
| output `backend_type` → `secret_store_backend_type`                          | Only matters if you read it directly; `retool-helm` picks it up from `outputs`.   |
| output `alb_controller_irsa_role_arn` / `_name`                              | Now `alb_controller_role_arn` / `_name` on `aws-eks`.                             |
| new `create_namespace`, `retool_namespace`                                   | Optional. See the namespace change below.                                         |
| new `eso_controller_role_arns`                                               | Only needed when your platform team runs the External Secrets Operator.           |

On `aws-eks`, all new and all defaulting `true` except where noted:
`enable_external_secrets`, `enable_cert_manager`, `enable_alb_controller`,
`enable_reloader`, `install_crds`, `make_default_ingress_class` (default
`false`), `enable_coredns_addon`, `enable_kube_proxy_addon`,
`enable_vpc_cni_addon`, `enable_pod_identity_agent`, plus `existing_cluster`,
`external_secrets_assumable_role_arns`, `external_secrets_serve_v1beta1`,
`reloader_auto_reload_all`, `pod_node_selector` and `pod_tolerations`.

#### Three behaviour changes that are easy to miss

**Retool moves out of the `default` namespace.** `retool-helm` previously
installed into `default`; it now follows `aws-retool-services`'s
`retool_namespace`, which defaults to `<prefix>-retool`. The namespace is
ForceNew, so this **recreates the Retool release**. To stay put, set
`retool_namespace = "default"` and `create_namespace = false` on
`aws-retool-services` — see
[pin to the old namespace](./troubleshooting.md#fix-3--pin-to-the-old-namespace).

**The ALB IngressClass stops being the cluster default.** It was hardcoded
`ingressClassConfig.default = true`; it is now `make_default_ingress_class`,
defaulting `false`, so applying strips
`ingressclass.kubernetes.io/is-default-class` from the `alb` IngressClass. Retool
routes via a `TargetGroupBinding` and never needed it, but anything else in the
cluster relying on a default class will break. Set
`make_default_ingress_class = true` on `aws-eks` to keep the old behaviour.

**`aws-user-ingress` takes an object instead of a namespace string.**
`retool_service_namespace = "default"` becomes
`retool_services = module.retool-services.outputs`.

#### The External Secrets IAM model changed

Previously each deployment's `${prefix}-eso` role was attached directly to the
bundled operator's service account by an `aws_eks_pod_identity_association`.

Now the cluster's single ESO controller has its own role — created by `aws-eks`,
associated with `external-secrets/external-secrets` via pod identity — and
*assumes* each deployment's `${prefix}-eso` role, selected by
`spec.provider.aws.role` on that deployment's `SecretStore`. Per-deployment least
privilege is preserved: one Retool deployment still cannot read another's
secrets.

The `${prefix}-eso` role and policy keep their names and state addresses; only
the trust policy changes, in place. If your platform team runs the operator
instead, set `eso_controller_role_arns` on `aws-retool-services` to its
controller's role ARN — otherwise `terraform plan` fails a precondition telling
you so.

#### Migration

Because the charts keep the namespaces and release names they already had, the
Helm releases can simply change hands. Add these `moved` blocks to your **root**
configuration — a module cannot declare moves for another module's resources —
and the three unchanged releases are upgraded in place instead of being
uninstalled and reinstalled. They assume your module calls are named `eks` and
`retool-services`, as in the examples; adjust if yours differ:

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

> [!WARNING]
> **Do not skip the `moved` blocks for external-secrets.** Without them
> Terraform destroys the old release and creates the new one with no dependency
> between the two, so it may uninstall the old release *last* — and the ESO
> chart templates its CRDs instead of shipping them in `crds/`, so that
> uninstall deletes the cluster-scoped CRDs the new release just created, taking
> every `SecretStore` and `ExternalSecret` with them. The symptom is an ESO pod
> logging `CustomResourceDefinition ... "externalsecrets.external-secrets.io" not
> found` while its Deployment looks healthy. `aws-eks` now stamps
> `helm.sh/resource-policy: keep` on these CRDs so they survive any future
> uninstall, but that only protects CRDs created by the new release — the ones
> already in your cluster carry no such annotation.

If you have already hit this and the CRDs are gone, reinstall the release to
recreate them, then apply again so the `SecretStore` and `ExternalSecret`s are
recreated on top:

```
terraform apply -replace='module.eks.helm_release.external_secrets[0]'
terraform apply
```

Verify:

```
kubectl get crd | grep external-secrets.io
kubectl get externalsecrets -A
```

Two chart-version bumps ride along: External Secrets `0.12.1` → `2.8.0` and
cert-manager `v1.11.0` → `v1.21.0`. cert-manager `v1.11.0` is years past EOL and
is not supported on Kubernetes 1.32, so that bump is not optional in practice.

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

#### If Helm refuses to adopt a resource

Skipping the `moved` blocks — or coming from a state where these charts ran in a
per-deployment namespace — leaves the cluster-scoped objects annotated with the
old release's ownership, and Helm refuses to adopt them:

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
#   ./adopt-helm-ownership.sh            # show what would change
#   DRY_RUN=0 ./adopt-helm-ownership.sh  # actually change it
#
set -euo pipefail

KUBECTL="${KUBECTL:-kubectl}"
DRY_RUN="${DRY_RUN:-1}"

# Target coordinates — must match what modules/aws-eks installs.
ESO_RELEASE="${ESO_RELEASE:-external-secrets}"
ESO_NAMESPACE="${ESO_NAMESPACE:-external-secrets}"
CERT_MANAGER_RELEASE="${CERT_MANAGER_RELEASE:-cert-manager}"
CERT_MANAGER_NAMESPACE="${CERT_MANAGER_NAMESPACE:-cert-manager}"
ALB_RELEASE="${ALB_RELEASE:-alb-controller}"
ALB_NAMESPACE="${ALB_NAMESPACE:-alb-controller}"
RELOADER_RELEASE="${RELOADER_RELEASE:-reloader}"
RELOADER_NAMESPACE="${RELOADER_NAMESPACE:-reloader}"

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

echo "== cert-manager -> ${CERT_MANAGER_RELEASE}/${CERT_MANAGER_NAMESPACE}"
restamp "$CERT_MANAGER_RELEASE" "$CERT_MANAGER_NAMESPACE" \
  $(crds_in_group cert-manager.io) \
  $(crds_in_group acme.cert-manager.io) \
  mutatingwebhookconfiguration/cert-manager-webhook \
  validatingwebhookconfiguration/cert-manager-webhook

echo "== AWS Load Balancer Controller -> ${ALB_RELEASE}/${ALB_NAMESPACE}"
restamp "$ALB_RELEASE" "$ALB_NAMESPACE" \
  $(crds_in_group elbv2.k8s.aws) \
  mutatingwebhookconfiguration/alb-controller-webhook \
  validatingwebhookconfiguration/alb-controller-webhook \
  ingressclass/alb

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

### metrics-server moved from `aws-retool-services` to `aws-eks`

metrics-server is now installed by `aws-eks` as an EKS-managed addon in
`kube-system`, rather than by `aws-retool-services` as a Helm release. Move the
`enable_metrics_server` variable to your `aws-eks` module block if you set it
(it still defaults to `true`).

Just apply. The old Helm release is uninstalled and the addon created in the same
run. The two have no dependency between them, so if Terraform happens to
uninstall last it can delete the cluster-scoped `metrics.k8s.io` APIService the
new addon just took over. Check afterwards:

```
kubectl top nodes
```

If that fails, re-create the addon:

```
terraform apply -replace='module.eks.aws_eks_addon.metrics_server[0]'
```

### AWS Karpenter Pod Identity errors

If you're on AWS, you will likely also hit an error like `Error: creating EKS Pod Identity Association`. To address, follow the troubleshooting guidance to [re-import the existing association](./troubleshooting.md#fix-import-the-existing-association).
