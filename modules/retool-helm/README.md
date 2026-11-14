## `retool-helm` module

This is a Terraform module wrapper around the official [`retool-helm`](https://github.com/tryretool/retool-helm/) Helm chart.

> [!NOTE] This module is designed to be used in conjunction with the other cloud-specific modules in [`retool-self-hosted-blueprints`](https://github.com/tryretool/retool-self-hosted-blueprints). See the [usage examples](https://github.com/tryretool/retool-self-hosted-blueprints/tree/main/examples) for references on how to use this module.

### App hostnames

When `enable_app_hostnames` is on in the `*-retool-services` module, this module
turns on the chart's app serving layer (`rr.appServingLayer`) at
`apps.<domain_name>` and sets `rr.agentSandbox.wildcardSandboxes`. See
[App hostnames](../../README.md#app-hostnames) in the root README.

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
