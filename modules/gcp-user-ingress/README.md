## `gcp-user-ingress` module

This is a Terraform module which provides the recommended user-facing (ingress) networking stack for production Retool deployments on GCP.

* Creates a Cloud DNS managed zone at the given domain name (`var.domain_name`)
* Creates a Google-managed certificate with DNS authorization
* Creates a GKE Gateway with HTTPS listener and HTTP-to-HTTPS redirect
* Installs [external-dns](https://github.com/kubernetes-sigs/external-dns) for automatic DNS record management

> [!NOTE] This module is intended to be used in conjunction with the other GCP-specific modules in [`retool-self-hosted-blueprints`](https://github.com/tryretool/retool-self-hosted-blueprints). See the [usage examples](https://github.com/tryretool/retool-self-hosted-blueprints/tree/main/examples) for references on how to use this module.
