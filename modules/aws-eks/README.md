## `aws-eks` module

This is a Terraform module wrapper around the existing [AWS EKS Terraform module](https://registry.terraform.io/modules/terraform-aws-modules/eks/aws/latest), but with defaults and options tuned for production Retool self-hosted deployments.

Alongside the cluster itself it installs the cluster-wide addons a Retool deployment needs:

* [Karpenter](https://karpenter.sh/) for node autoscaling (`enable_karpenter`)
* The [EBS CSI driver](https://github.com/kubernetes-sigs/aws-ebs-csi-driver) for persistent volume support (`enable_ebs_csi_driver`)
* [Metrics Server](https://github.com/kubernetes-sigs/metrics-server), as an EKS-managed addon, for `kubectl top` / HPA (`enable_metrics_server`)

> [!NOTE] This module is designed to be used in conjunction with the other AWS-specific modules in [`retool-self-hosted-blueprints`](https://github.com/tryretool/retool-self-hosted-blueprints). See the [usage examples](https://github.com/tryretool/retool-self-hosted-blueprints/tree/main/examples) for references on how to use this module.
