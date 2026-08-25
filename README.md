# Retool self-hosted blueprints

This is a collection of Terraform modules and usage examples for deploying and
managing a self-hosted Retool deployment in your own cloud provider (AWS, GCP,
or Azure).

Each "all-inclusive" example stands up everything a deployment needs —
network, Kubernetes cluster, managed Postgres, secrets, ingress, and the Retool
Helm release — so you can go from an empty cloud project to a running Retool in
a single `terraform apply`.

## Repository layout

- [`modules/`](./modules) — the building-block Terraform modules (one set per
  cloud, plus the cloud-agnostic [`retool-helm`](./modules/retool-helm) module).
- [`examples/`](./examples) — copy-paste starting points that wire the modules
  together. Start here.
- [`guides/`](./guides) — topic guides that apply across clouds (e.g.
  [scaling](./guides/scaling.md)).

## Requirements

- [Terraform](https://developer.hashicorp.com/terraform/install) **>= 1.11**
  for the Azure and AWS modules (they use write-only secret arguments introduced
  in 1.11). The GCP modules run on **>= 1.5.7** so they can deploy via GCP
  Marketplace / Infrastructure Manager.
  > **GCP secret handling:** Because 1.5.7 predates write-only arguments, the
  > GCP modules write generated secrets (DB password, encryption key, JWT secret)
  > and any `license_key` you pass into Terraform state. Use a remote,
  > encrypted, access-restricted backend (e.g. a GCS bucket with CMEK + tight
  > IAM). To keep specific secrets out of state entirely, pre-create them in
  > Secret Manager and pass them by name via `encryption_key_secret_name` /
  > `license_key_secret_path`.
- [Helm v3+](https://helm.sh/docs/intro/install)
- [`kubectl`](https://kubernetes.io/docs/tasks/tools/)
- The CLI for your cloud, authenticated with admin credentials:
  - AWS: [`aws`](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) (`aws sso login` / configured credentials)
  - GCP: [`gcloud`](https://cloud.google.com/sdk/docs/install) (`gcloud auth application-default login`)
  - Azure: [`az`](https://learn.microsoft.com/cli/azure/install-azure-cli) (`az login`)
- The [`helm-git`](https://github.com/aslafy-z/helm-git) Helm plugin **only if**
  you deploy an unpublished chart branch (see
  [Testing an unpublished Helm chart branch](#testing-an-unpublished-helm-chart-branch)).

## Getting started

1. **Pick an example** under [`examples/`](./examples) for your cloud. The
   `*_all_inclusive` examples deploy the standard stack; the
   `*_all_inclusive_r2_beta` examples additionally enable the agent sandbox and
   Remote Repository storage. Each example has its own `README.md` with
   cloud-specific notes.

   Already running Retool on AWS ECS/Fargate via the
   [`retool-onpremise`](https://github.com/tryretool/retool-onpremise)
   CloudFormation templates? Start from
   [`aws_import_from_cloudformation`](./examples/aws_import_from_cloudformation)
   instead — it keeps your existing VPC and databases, runs the new deployment
   alongside the old one, and cuts over by moving DNS. It ships a helper that
   reads your CloudFormation stack and writes most of the configuration for you,
   and is configured with variables rather than a `locals` block.

2. **Copy the example** into your own Terraform working directory (or work in
   place), then turn the provider stub into a real config:

   ```sh
   mv provider.example.tf provider.tf
   ```

   Use `mv`, not `cp`: Terraform loads every `*.tf` file in the directory, and
   `provider.example.tf` matches, so keeping both declares each provider twice.

3. **Edit the `locals` block** at the top of `main.tf` — set `prefix`,
   your cloud project/subscription, `region`, and `domain_name`. (The
   `aws_import_from_cloudformation` example instead uses variables: copy
   `vars.tf.example` to `terraform.tfvars` and edit that.)

4. **Deploy:**

   ```sh
   terraform init
   terraform plan
   terraform apply
   ```

5. **Point DNS at the deployment.** The ingress module provisions a managed
   zone / load balancer; delegate your domain (or create the relevant record)
   so `domain_name` resolves to it. See the example README for specifics.

6. **Open Retool** at `https://<your domain_name>`.

> [!TIP]
> First time with Terraform? Run `terraform plan` before every `apply` to see
> exactly what will change. State is stored locally by default — configure a
> [remote backend](https://developer.hashicorp.com/terraform/language/backend)
> for team use.

## Setting the Retool license key

Without a license key the deployment runs in free-tier mode. There are two ways
to supply one — the **Secret Manager path is recommended** because the key never
lives in Terraform state or your `.tf` files:

1. **Recommended — dedicated secret.** Leave `license_key` unset, store the key
   in a cloud secret you manage yourself, and point the `license_key_secret_path`
   variable on the `*-retool-services` module at it. The key never enters
   Terraform state. Each example README has a copy-paste one-liner for its cloud.

2. **Quick — plaintext variable.** Set `license_key = "..."` on the
   `*-retool-services` module. Simplest, but the key is stored in Terraform
   state.

## Scaling

See the [scaling guide](./guides/scaling.md) for how to size the database and
scale the Retool services (replica counts, resource requests/limits) via
`retool_helm_extra_values`.

## Testing an unpublished Helm chart branch

By default the modules install the published Retool chart from
`https://charts.retool.com`. To test an unreleased chart branch, set
`retool_helm_chart_use_unpublished_branch` on the `retool-helm` module (the
`*_r2_beta` examples do this with the `r2` branch). This pulls the chart from
git, which requires the [`helm-git`](https://github.com/aslafy-z/helm-git)
plugin:

```sh
helm plugin install https://github.com/aslafy-z/helm-git
```

If the plugin is missing, `terraform apply` fails when fetching the chart. The
default (published-chart) path needs no extra plugins.
