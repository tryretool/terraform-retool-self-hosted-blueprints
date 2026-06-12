# GCP all-inclusive example

Deploys a complete self-hosted Retool stack on GCP: a VPC, a GKE cluster, a
Cloud SQL (Postgres) instance, secrets in Secret Manager, user ingress (managed
DNS zone + certificate), and the Retool Helm release.

See the [repository README](../../README.md) for general prerequisites and
Terraform basics. This file covers GCP-specific setup.

## Quick start

```sh
cp provider.example.tf provider.tf
# edit the locals block in main.tf: prefix, project_id, region, domain_name
gcloud auth application-default login   # if you haven't already
terraform init
terraform plan
terraform apply
```

After apply, delegate your domain to the managed DNS zone that was created (add
its name servers as NS records at your registrar) so `domain_name` resolves to
the deployment, then open `https://<domain_name>`.

## Required GCP APIs

The modules enable the APIs they need, but enablement on a brand-new project can
take a minute to propagate — and Terraform may try to use an API before it's
ready, causing an apply to fail (for example, a `Certificate Manager API has not
been used in project ...` error). Re-running `terraform apply` usually
succeeds once propagation completes.

To avoid the race entirely, pre-enable everything up front:

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

The recommended path keeps the key out of Terraform state: store it in a Secret
Manager secret you own and point the `license_key_secret_path` input at it.
Create the secret:

```sh
printf '<your-license-key>' | \
  gcloud secrets create retool-<prefix>-license-key --data-file=- --replication-policy=automatic
```

Then set it on the `gcp-retool-services` module and apply:

```hcl
module "retool-services" {
  # ...
  license_key_secret_path = "retool-<prefix>-license-key"
}
```

## Troubleshooting

### Cloud SQL: `409 instance already exists` after a timeout

Cloud SQL instance creation can take longer than Terraform's client-side
timeout. When that happens the create operation **keeps running on the server**,
so the instance ends up created even though Terraform reported an error — and a
retry then fails with `Error 409: The Cloud SQL instance already exists`.

To recover:

1. Check the [Cloud SQL console](https://console.cloud.google.com/sql/instances)
   — if the instance is `RUNNABLE`, the create actually succeeded.
2. Import it into state so Terraform stops trying to create it, e.g.:
   ```sh
   terraform import 'module.db-main.module.pg.google_sql_database_instance.default' \
     <project-id>:<region>:<instance-name>
   ```
   (the instance name is in the error message), then `terraform apply` again.
3. If you instead delete the instance to start over, note that Cloud SQL
   **reserves a deleted instance name for ~1 week** — it can't be reused
   immediately. The module appends a random suffix, so a fresh apply gets a new
   name.

## Scaling

The default `db-g1-small` tier needs a higher connection ceiling for the full
stack, which is why this example sets `max_connections = 300`. See the
[scaling guide](../../guides/scaling.md) for sizing the database and services.
