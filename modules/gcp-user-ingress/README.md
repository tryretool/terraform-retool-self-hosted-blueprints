## `gcp-user-ingress` module

This is a Terraform module which provides the recommended user-facing (ingress) networking stack for production Retool deployments on GCP.

* Creates a Cloud DNS managed zone at the given domain name (`var.domain_name`)
* Creates a Google-managed certificate with DNS authorization
* Creates a GKE Gateway with HTTPS listener and HTTP-to-HTTPS redirect
* Installs [external-dns](https://github.com/kubernetes-sigs/external-dns) for automatic DNS record management

### R² app hostnames

Set `enable_apps_domain = true` (with `enable_apps_domain` on `retool-helm`) to
route `*.apps.<domain_name>` to the app serving layer and
`*.sandboxes.apps.<domain_name>` to the agent-sandbox proxy. The module adds a
second Google-managed certificate for both wildcards, with its own DNS
authorizations and certificate map entries, so the existing certificate is not
replaced. It also adds an HTTPRoute and a HealthCheckPolicy for each backend.
external-dns publishes the two wildcard records from the HTTPRoutes.

> [!NOTE] This module is intended to be used in conjunction with the other GCP-specific modules in [`retool-self-hosted-blueprints`](https://github.com/tryretool/retool-self-hosted-blueprints). See the [usage examples](https://github.com/tryretool/retool-self-hosted-blueprints/tree/main/examples) for references on how to use this module.
