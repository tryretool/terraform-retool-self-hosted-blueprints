# GCP — deploy into a shared / existing GKE cluster

Deploys Retool into a pre-existing GKE cluster rather than creating one. It
instantiates `gcp-gke` with `existing_cluster`, which adopts the cluster and
installs only the cluster-wide operators Retool needs (External Secrets
Operator, reloader), and puts the Retool deployment itself in a single
`<prefix>-retool` namespace. Each operator has an `enable_*` toggle — turn off
whatever your platform team already runs.

`external-dns` is not a cluster singleton and stays per-deployment, scoped to the
DNS zone this example creates.

Read [`guides/shared-clusters.md`](../../guides/shared-clusters.md) first — it
explains the namespace model, why the operators are singletons, and how the
External Secrets Operator reaches Retool's secrets.

## Cluster prerequisites

- Workload Identity enabled (used by ESO and external-dns). Checked at plan time.
- Gateway API enabled (GKE `gateway_api_config`), since user ingress uses a
  Gateway API `Gateway` + `HTTPRoute`. Also checked at plan time; set
  `enable_gateway_api_check = false` on `gcp-gke` if you route ingress another way.
- Private service access configured on the VPC so Cloud SQL is reachable on its
  private IP.

## Before you apply

1. Copy `provider.example.tf` and set your project/region.
2. In `main.tf`, set the `locals` for your existing infrastructure:
   `cluster_name`, `cluster_location`, `vpc_network_id`, and `domain_name`.
3. Confirm no other Terraform state already owns the cluster-wide operators —
   only one may install them. If another Retool deployment already runs in this
   cluster, drop the `gke` module block and keep the rest.
4. If your platform team runs the External Secrets Operator, set
   `enable_external_secrets = false` on `gcp-gke` and bind its controller to
   `module.retool-services.outputs.eso_gcp_service_account_email`, or copy the
   per-secret IAM grants onto whatever identity it uses.
5. If you set `enable_external_dns = false`, point your existing external-dns at
   the Cloud DNS zone this example creates, or create the A record manually from
   `module.user-ingress.outputs.static_ip_address`.

## See also

- [Upgrades](../../guides/upgrade-v0.md) — migrating an existing deployment.
- [Troubleshooting](../../guides/troubleshooting.md)
- [Scaling](../../guides/scaling.md)
