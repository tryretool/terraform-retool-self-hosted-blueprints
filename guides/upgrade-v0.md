# Upgrades 

## Unreleased

### Helm release namespace consolidation

The modules for `retool-helm`, `<cloud>-retool-services`, and
`<cloud>-user-ingress` use `helm_release` resources to deploy various components
into the Kubernetes cluster. To support deploying multiple Retool instances into
a single [shared or separately managed Kubernetes cluster](./shared-clusters.md), the default namespaces used by these Helm releases changed.

* `<prefix>-retool` - used exclusively by `retool-helm` for Retool proper
* `<prefix>-retool-services` - used by all the various Helm releases and other resources in `<cloud>-retool-services` and `<cloud>-user-ingress`

When applied, these namespace changes will likely cause Helm errors like this:

```
Error: Unable to continue with install: CustomResourceDefinition
"acraccesstokens.generators.external-secrets.io" in namespace "" exists and
cannot be imported into the current release: invalid ownership metadata;
annotation validation error: key "meta.helm.sh/release-namespace" must equal
"<prefix>-retool-services": current value is "external-secrets"
```

To address, follow the steps in [delete the conflicting resources and re-apply](./troubleshooting.md#fix-1-delete-conflicting-resources-and-re-apply)

### AWS Karpenter Pod Identity errors

If you're on AWS, you will likely also hit an error like `Error: creating EKS Pod Identity Association`. To address, follow the troubleshooting guidance to [re-import the existing association](./troubleshooting.md#fix-import-the-existing-association).
