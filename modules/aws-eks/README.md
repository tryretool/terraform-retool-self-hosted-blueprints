## `aws-eks` module

This is a Terraform module wrapper around the existing [AWS EKS Terraform module](https://registry.terraform.io/modules/terraform-aws-modules/eks/aws/latest), but with defaults and options tuned for production Retool self-hosted deployments.

Alongside the cluster itself it installs the cluster-wide addons and operators a Retool deployment needs:

* [Karpenter](https://karpenter.sh/) for node autoscaling (`enable_karpenter`)
* The [EBS CSI driver](https://github.com/kubernetes-sigs/aws-ebs-csi-driver) for persistent volume support (`enable_ebs_csi_driver`)
* [Metrics Server](https://github.com/kubernetes-sigs/metrics-server), as an EKS-managed addon, for `kubectl top` / HPA (`enable_metrics_server`)
* The [External Secrets Operator](https://external-secrets.io/latest/) (`enable_external_secrets`), with a pod-identity role that each deployment's `<prefix>-eso` role trusts
* [cert-manager](https://cert-manager.io/) (`enable_cert_manager`), which issues the ALB controller's admission webhook certificate
* The [AWS Load Balancer Controller](https://kubernetes-sigs.github.io/aws-load-balancer-controller/latest/) (`enable_alb_controller`), with its service account and IAM permissions
* [Stakater reloader](https://github.com/stakater/Reloader) (`enable_reloader`), which restarts workloads when the ConfigMaps and Secrets they reference change
* The core EKS addons — CoreDNS, kube-proxy, VPC CNI and the Pod Identity agent (`enable_coredns_addon`, `enable_kube_proxy_addon`, `enable_vpc_cni_addon`, `enable_pod_identity_agent`)

Every one of them is a **cluster-wide singleton**: each owns CRDs, admission webhooks and/or ClusterRoles whose names are fixed by the chart, so exactly one copy can exist per cluster and none of them can be installed once per Retool deployment. Each has an enable toggle so a cluster that already runs one — or manages it out of band — can be adopted without a second copy fighting over it.

## Deploying into an existing cluster

Set `existing_cluster` to adopt a cluster this module did not create. No cluster, KMS key, VPC or node group is created; the cluster's attributes are read from the live cluster and only the addons and operators above are installed. Instantiate the module **once per cluster**, then deploy `aws-retool-services` + `retool-helm` + `aws-user-ingress` once per Retool instance. See [`guides/shared-clusters.md`](../../guides/shared-clusters.md) and [`examples/aws_shared_cluster`](../../examples/aws_shared_cluster).

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

`enable_karpenter` must be `false` for an adopted cluster: Karpenter's IAM is wired to the controller node group this module creates alongside a new cluster.

> [!NOTE] This module is designed to be used in conjunction with the other AWS-specific modules in [`retool-self-hosted-blueprints`](https://github.com/tryretool/retool-self-hosted-blueprints). See the [usage examples](https://github.com/tryretool/retool-self-hosted-blueprints/tree/main/examples) for references on how to use this module.
