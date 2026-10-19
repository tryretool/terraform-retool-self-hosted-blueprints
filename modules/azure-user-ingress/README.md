## `azure-user-ingress` module

This is a Terraform module which provides the recommended user-facing (ingress) networking stack for production Retool deployments on Azure.

* Creates an Azure DNS zone at the given domain name (`var.domain_name`)
* Creates an Application Gateway v2 with preconfigured listeners, routing rules, and health probes for serving Retool traffic
* Installs [Application Gateway Ingress Controller (AGIC)](https://azure.github.io/application-gateway-kubernetes-ingress/) with Workload Identity federation
* Optionally installs [cert-manager](https://cert-manager.io/) for automated Let's Encrypt TLS via DNS-01 challenge

### R² app hostnames

`enable_apps_domain` on the `*-retool-services` module routes
`*.apps.<domain_name>` to the app serving layer, and `enable_wildcard_sandboxes`
there also routes `*.sandboxes.apps.<domain_name>` to the agent-sandbox proxy.
This module reads both from `retool_services`. The module creates one
Ingress per hostname, because AGIC gives every listener in an Ingress the same
rule priority. With `enable_https`, it adds a second cert-manager Certificate for
the routed wildcards, so the existing certificate is not replaced. With
`enable_agic`, it adds an A record for each.

> [!NOTE] This module is intended to be used in conjunction with the other Azure-specific modules in [`retool-self-hosted-blueprints`](https://github.com/tryretool/retool-self-hosted-blueprints). See the [usage examples](https://github.com/tryretool/retool-self-hosted-blueprints/tree/main/examples) for references on how to use this module.
