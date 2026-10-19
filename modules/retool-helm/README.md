## `retool-helm` module

This is a Terraform module wrapper around the official [`retool-helm`](https://github.com/tryretool/retool-helm/) Helm chart.

> [!NOTE] This module is designed to be used in conjunction with the other cloud-specific modules in [`retool-self-hosted-blueprints`](https://github.com/tryretool/retool-self-hosted-blueprints). See the [usage examples](https://github.com/tryretool/retool-self-hosted-blueprints/tree/main/examples) for references on how to use this module.

### R² app hostnames

`enable_apps_domain = true` turns on the chart's app serving layer
(`rr.appServingLayer`) at `apps.<domain_name>`, in-process on the main backend.
It requires `domain_name`, the agent sandbox, and an R² bucket
(`retool_services.agent_sandbox_enabled` and `rr_bucket_k8s_secret_name`),
because the serving layer reads published apps from the git server's storage.
It needs chart 6.13.0+ and Retool 4.78.0+. Pair it with `enable_apps_domain` on
the cloud's `*-user-ingress` module, which adds the certificate, DNS and routes.

`enable_wildcard_sandboxes = true` additionally sets
`rr.agentSandbox.wildcardSandboxes`, which serves each editor preview at
`sandbox-<id>.sandboxes.apps.<domain_name>`. Turn it on in a later apply, after
the ingress module's certificate is issued: it moves every editor preview as soon
as the chart rolls out.
