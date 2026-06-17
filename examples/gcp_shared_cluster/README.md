# GCP — deploy into a shared / existing GKE cluster

Deploys Retool into a pre-existing GKE cluster rather than creating one. It
deploys only the Retool-specific pieces into dedicated, prefixed namespaces and
assumes the cluster already runs the common operators (External Secrets
Operator, external-dns).

Read [`guides/shared-clusters.md`](../../guides/shared-clusters.md) first — it
explains the namespace model, the `enable_*` toggles, and how to grant the
platform's ESO access to Retool's secrets.

## Cluster prerequisites

- Workload Identity enabled (used by ESO and external-dns).
- Gateway API CRDs present (GKE `gateway_api_config`), since user ingress uses a
  Gateway API `Gateway` + `HTTPRoute`.
- Private service access configured on the VPC so Cloud SQL is reachable on its
  private IP.

## Before you apply

1. Copy `provider.example.tf` and set your project/region.
2. In `main.tf`, set the `locals` for your existing infrastructure:
   `cluster_name`, `cluster_location`, `vpc_network_id`, and `domain_name`.
3. Grant the platform's External Secrets Operator access to Retool's secrets:
   bind it to (or copy the per-secret IAM grants onto)
   `module.retool-services.outputs.eso_gcp_service_account_email`.
4. If you leave `enable_external_dns = false`, point your existing external-dns
   at the Cloud DNS zone this example creates, or create the A record manually
   from `module.user-ingress.outputs.static_ip_address`.
