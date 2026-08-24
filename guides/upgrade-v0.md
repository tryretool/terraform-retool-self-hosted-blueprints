# Upgrades 

## Unreleased

### Cluster-wide operators moved to the cluster module — all clouds

**Breaking on AWS, GCP and Azure.** The External Secrets Operator, cert-manager
and Stakater reloader are cluster singletons: each owns CRDs, admission webhook
configurations and/or ClusterRoles whose names are fixed by the chart, so only
one copy can exist per cluster and they cannot be installed once per Retool
deployment. They now install from the cluster module — `aws-eks`, `gcp-gke` or
`azure-aks` — and `<cloud>-retool-services` keeps only what is genuinely
per-deployment.

Each cluster module also gains an `existing_cluster` input so it can adopt a
cluster it did not create, which is how a shared-cluster deployment gets the
operators. Instantiate it once per cluster; deploy `<cloud>-retool-services`,
`retool-helm` and `<cloud>-user-ingress` once per Retool instance.

Common to every cloud:

* `services_namespace` is gone. The operators use their conventional namespaces
  and the Retool deployment keeps a single `<prefix>-retool`.
* `create_namespaces` is renamed **`create_namespace`** — only one namespace
  remains.
* `pod_node_selector` / `pod_tolerations` move from `<cloud>-retool-services` to
  the cluster module. They stay on `retool-helm` and on the GCP/Azure
  user-ingress modules.
* Every operator gets an `enable_*` toggle on the cluster module, all defaulting
  `true`, plus `install_crds` and `reloader_auto_reload_all`.
* The `moved` blocks below go in your **root** configuration — a module cannot
  declare moves for another module's resources. They assume your module calls are
  named as in the examples; adjust if yours differ.

Per-cloud detail follows. Read the section for the clouds you run.

### AWS

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

#### AWS — config changes you must make by hand

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

#### AWS — three behaviour changes that are easy to miss

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

#### AWS — the External Secrets IAM model changed

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

#### AWS — migration

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
terraform apply -replace='module.eks.helm_release.external_secrets[0]'   # or module.gke / module.aks
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

#### AWS — metrics-server moved to `aws-eks`

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

#### AWS — Karpenter Pod Identity errors

You will likely also hit an error like `Error: creating EKS Pod Identity
Association`. To address, follow the troubleshooting guidance to
[re-import the existing association](./troubleshooting.md#fix--import-the-existing-association).

### GCP

Only the External Secrets Operator and reloader move: GCP has no in-cluster
ingress controller (the GKE Gateway controller runs in the control plane) and no
cert-manager (TLS comes from Google Certificate Manager). `external-dns` stays
per-deployment — it owns no CRDs and no webhooks, so prefixing its release name
is enough for several to coexist.

#### GCP — config changes you must make by hand

| Change | What to do |
|---|---|
| `enable_external_secrets`, `enable_reloader`, `install_crds` removed from `gcp-retool-services` | Same names on `gcp-gke`. |
| `external_secrets_chart`, `reloader_chart` removed | Same names on `gcp-gke`. |
| `services_namespace` removed, `create_namespaces` → `create_namespace` | See the shared notes above. |
| `pod_node_selector` / `pod_tolerations` removed from `gcp-retool-services` | Same names on `gcp-gke`. |
| `gke` input now takes `module.gke.outputs` | It already did in the all-inclusive examples; shared-cluster roots that hand-built the object should pass the module's outputs instead. |
| output `services_namespace` | Gone. |

#### GCP — the SecretStore is now genuinely namespaced

The previous release exported `secret_store_kind = "SecretStore"` and
`secret_store_name = "retool-secretstore"` but actually deployed a
`ClusterSecretStore` named `gcp-secretsmanager` — a fixed cluster-scoped name
that collides between deployments. It is now a real namespaced `SecretStore` in
`<prefix>-retool`, matching what the outputs always claimed.

Its `serviceAccountRef` also changes. It used to point at the bundled operator's
own service account in the services namespace; it now points at a per-deployment
`retool-eso` service account in `<prefix>-retool`, annotated with this
deployment's Google service account. That is what keeps deployments isolated once
a single controller serves them all.

The Workload Identity binding changes resource type as part of this —
`google_service_account_iam_binding` to `google_service_account_iam_member`.
`_binding` is authoritative for the whole role, so with several deployments the
last apply would evict the others. Terraform will destroy the old binding and
create the member; that is expected and momentary.

#### GCP — migration

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
them. The ESO CRD warning below applies — read it before applying.

`external-dns` is renamed from `external-dns` to `<prefix>-external-dns` and
moves into `<prefix>-retool`, so it is replaced too. Its DNS records are
unaffected: `txtOwnerId` is unchanged, and its policy is `upsert-only`.


### Azure

The External Secrets Operator, cert-manager and reloader all move to
`azure-aks`. AGIC stays in `azure-user-ingress`: it binds 1:1 to an Application
Gateway, and the chart supports multiple instances as long as each has its own
release name, IngressClass and watch namespace.

#### Azure — config changes you must make by hand

| Change | What to do |
|---|---|
| `enable_external_secrets`, `enable_reloader`, `install_crds` removed from `azure-retool-services` | Same names on `azure-aks`. |
| `enable_cert_manager`, `install_crds` removed from `azure-user-ingress` | `enable_cert_manager` moves to `azure-aks`. |
| `services_namespace` removed, `create_namespaces` → `create_namespace` | See the shared notes above. |
| `pod_node_selector` / `pod_tolerations` removed from `azure-retool-services` | Same names on `azure-aks`. |
| `aks` input on `azure-user-ingress` | Must now be `module.aks.outputs` — it needs `cert_manager_service_account_subject`, not just `oidc_issuer_url`. |
| `ingress_class_name` default | Was `azure-application-gateway`; now `<prefix>-agic`. Set it explicitly to keep the old value. |
| output `services_namespace` | Gone. |
| output `cluster_issuer_name` | Still present, but now names a namespaced `Issuer` by default; the new `issuer_kind` output says which. |

#### Azure — the certificate issuer is now namespaced

cert-manager is shared, but a `ClusterIssuer` named `letsencrypt-prod` is not:
the name is cluster-global and so is its ACME account key Secret. Each
deployment now gets an `Issuer` named `<prefix>-letsencrypt` in `<prefix>-retool`
with a `<prefix>-letsencrypt-account-key`.

The identity model follows the same split as ESO. cert-manager has no per-Issuer
service account indirection — an Issuer names a managed identity and the
controller exchanges its **own** token for it — so each deployment's
`<prefix>-cert-manager-identity` now federates against the shared controller's
service account (`system:serviceaccount:cert-manager:cert-manager`, exported as
`cert_manager_service_account_subject`), while its DNS Zone Contributor grant
stays scoped to its own zone. One controller, per-deployment DNS reach.

`retool-helm` emits `cert-manager.io/issuer` instead of
`cert-manager.io/cluster-issuer` when the issuer is namespaced, driven by the new
`issuer_kind` field on the `user_ingress` object. Passing
`user_ingress = module.user-ingress.outputs` picks this up automatically.

Setting `cluster_issuer_name` still switches to a `ClusterIssuer` you manage.

#### Azure — migration

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

All three change namespace, so they are replaced rather than upgraded. Read the
ESO CRD warning below first.

Every `azurerm_federated_identity_credential` is also recreated, because its
`subject` changes namespace. That is a metadata-only change on the Azure side —
the managed identities and their Key Vault and DNS grants keep their names and
state addresses.

Three chart bumps ride along on Azure: External Secrets `0.12.1` → `2.8.0`,
cert-manager `v1.17.1` → `v1.21.0`, reloader `2.2.9` → `2.2.14`. The ESO one
crosses the `external-secrets.io/v1beta1` → `/v1` API move, so set
`external_secrets_serve_v1beta1 = true` on `azure-aks` for the apply that
performs the upgrade and remove it afterwards — see the AWS section above for
why.

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
