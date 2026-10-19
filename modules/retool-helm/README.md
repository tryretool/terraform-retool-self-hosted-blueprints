## `retool-helm` module

This is a Terraform module wrapper around the official [`retool-helm`](https://github.com/tryretool/retool-helm/) Helm chart.

> [!NOTE] This module is designed to be used in conjunction with the other cloud-specific modules in [`retool-self-hosted-blueprints`](https://github.com/tryretool/retool-self-hosted-blueprints). See the [usage examples](https://github.com/tryretool/retool-self-hosted-blueprints/tree/main/examples) for references on how to use this module.

### R² app hostnames

When `retool_services.apps_domain_enabled` is true (`enable_apps_domain` on the
`*-retool-services` module), this module turns on the chart's app serving layer
(`rr.appServingLayer`) at `apps.<domain_name>`, in-process on the main backend.
It requires `domain_name`, the agent sandbox, and an R² bucket, because the
serving layer reads published apps from the git server's storage. It needs chart
6.13.0+ and Retool 4.78.0+. The cloud's `*-user-ingress` module reads the same
flag and adds the certificate, DNS and routes.

To run the serving layer as its own Deployment instead, for larger installs,
set the chart's `separate` values through `retool_helm_extra_values`. The
Service the ingress modules route to keeps its name, so nothing else changes:

```hcl
retool_helm_extra_values = [yamlencode({
  rr = {
    appServingLayer = {
      separate = {
        enabled      = true
        replicaCount = 2
      }
    }
  }
})]
```

`retool_services.wildcard_sandboxes_enabled` additionally sets
`rr.agentSandbox.wildcardSandboxes`, which serves each editor preview at
`sandbox-<id>.sandboxes.apps.<domain_name>`. It moves every editor preview as soon
as the chart rolls out.
