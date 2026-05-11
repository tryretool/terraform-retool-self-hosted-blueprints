## `aws-retool-services` module

This is a Terraform module which adds provides extensions to an EKS Kubernetes cluster and other supporting services and configurations recommended for running Retool self-hosted in EKS.

* Installs [AWS Load Balancer Controller](https://kubernetes-sigs.github.io/aws-load-balancer-controller/latest/)
  * Includes a default IngressClass and a suitable Service Account with necessary IAM permissions
* Installs [Metrics Server](https://github.com/kubernetes-sigs/metrics-server)
* Installs [External Secrets Operator](https://external-secrets.io/latest/)
  * Includes a suitable Service Account with necessary IAM permissions
* Creates an S3 bucket for use as git storage backend for Retool apps
* Installs ESO `ExternalSecret` resources for required Retool secrets so AWS SecretsManager remains the source of truth.

> [!NOTE] This module is intended to be used in conjunction with the other AWS-specific modules in [`retool-self-hosted-blueprints`](https://github.com/tryretool/retool-self-hosted-blueprints). See the [usage examples](https://github.com/tryretool/retool-self-hosted-blueprints/tree/main/examples) for references on how to use this module.
