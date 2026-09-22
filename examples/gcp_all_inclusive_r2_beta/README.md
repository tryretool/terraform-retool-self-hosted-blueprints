# GCP all-inclusive example (R2 beta)

Same complete GCP stack as [`gcp_all_inclusive`](../gcp_all_inclusive), with the
R2 features enabled: the **agent sandbox** (`enable_agent_sandbox`), **Remote
Repository GCS storage** (`enable_rr_gcs`), and the unreleased **`r2` Helm chart
branch**.

See the [repository README](../../README.md) for general prerequisites. This
file covers what's specific to GCP and to the R2 beta.

## Prerequisite: `helm-git`

This example sets `retool_helm_chart_use_unpublished_branch = "r2"`, which pulls
the Retool chart from git instead of the published repo. That requires the
[`helm-git`](https://github.com/aslafy-z/helm-git) Helm plugin:

```sh
helm plugin install https://github.com/aslafy-z/helm-git
```

Without it, `terraform apply` fails when fetching the chart.

## Quick start

```sh
mv provider.example.tf provider.tf
# edit the locals block in main.tf: prefix, project_id, region, domain_name
gcloud auth application-default login   # if you haven't already
terraform init
terraform plan
terraform apply
```

## Configure DNS

Same as the [base example](../gcp_all_inclusive/README.md#configure-dns). The
`gcp-user-ingress` module manages the `A` record (via `external-dns`) and the
Certificate Manager DNS authorization inside a Cloud DNS managed zone; you only
need to **delegate your domain** to it.

1. Get the managed zone's name servers:

   ```sh
   terraform output -json modules | jq -r '.["user-ingress"].zone_name_servers[]'
   ```

2. At your registrar (or parent-domain DNS provider), point the **`NS` record**
   for `domain_name` at those name servers.

3. Wait for DNS to propagate — `dig +short NS <domain_name>` should print the
   zone's name servers from step 1 once the change has propagated. The managed
   certificate then validates automatically and `https://<domain_name>` comes up.

## Required GCP APIs

Same as the base example — pre-enable to avoid API-propagation races on a new
project:

```sh
gcloud services enable \
  compute.googleapis.com \
  servicenetworking.googleapis.com \
  sqladmin.googleapis.com \
  container.googleapis.com \
  secretmanager.googleapis.com \
  dns.googleapis.com \
  certificatemanager.googleapis.com \
  --project <your-project-id>
```

## Setting the license key

This example sets `license_key` inline for convenience. The recommended,
state-free path is to leave it unset, store the key in a Secret Manager secret
you own, and point `license_key_secret_path` at it:

```sh
printf '<your-license-key>' | \
  gcloud secrets create retool-<prefix>-license-key --data-file=- --replication-policy=automatic
```

```hcl
module "retool-services" {
  # ...
  license_key_secret_path = "retool-<prefix>-license-key"
}
```

## Troubleshooting

### Cloud SQL: `409 instance already exists` after a timeout

Cloud SQL creation can outlast Terraform's client timeout; the instance is
created server-side even though the apply errors, and a retry then hits
`Error 409: The Cloud SQL instance already exists`. Check the
[Cloud SQL console](https://console.cloud.google.com/sql/instances) — if the
instance is `RUNNABLE`, import it and re-apply:

```sh
terraform import 'module.db-main.module.pg.google_sql_database_instance.default' \
  <project-id>:<region>:<instance-name>
```

Deleted instance names are reserved by Cloud SQL for ~1 week; the module appends
a random suffix so a fresh apply gets a new name.

## Scaling

This example sets `max_connections = 300` because the full stack (main +
workflows + agent sandbox) needs more connections than the `db-g1-small`
default. See the [scaling guide](../../guides/scaling.md).
