# Retool Blueprints (GCP Marketplace)

Deploys self-hosted Retool on Google Cloud: a VPC, GKE cluster, Cloud SQL
(Postgres), Secret Manager, Cloud DNS plus a managed certificate, and the
Retool Helm release.

Marketplace / Infrastructure Manager supplies `project_id` and rewrites image
and chart locations to Google-owned Artifact Registry copies. The
`provider "google"` block must live in `main.tf` (not another `.tf` file);
mpdev injects the consumption-tracking label there during publish. UI
deployment also requires `goog_cm_deployment_name` plus
`metadata.yaml` / `metadata.display.yaml` (regenerate with
`cft blueprint metadata -p marketplace/gcp -q -d --nested=false`). You still set:

- `domain_name` — hostname that will serve Retool (for example `retool.example.com`)
- `region` — defaults to `us-central1`
- `license_key` — optional; omit for free-tier mode

## After apply: delegate DNS

The module creates a Cloud DNS managed zone for `domain_name`. Point the
parent domain's NS records at that zone:

```sh
terraform output zone_name_servers
```

Once NS records propagate, ExternalDNS creates the A record and Certificate
Manager issues TLS. Open `https://<domain_name>`.

## Local apply (not Marketplace UI)

```sh
terraform init
terraform plan \
  -var="project_id=YOUR_PROJECT" \
  -var="domain_name=retool.example.com"
terraform apply \
  -var="project_id=YOUR_PROJECT" \
  -var="domain_name=retool.example.com"
```

Enable these APIs on a new project first, or re-run apply if enablement is
still propagating:

```sh
gcloud services enable \
  compute.googleapis.com \
  servicenetworking.googleapis.com \
  sqladmin.googleapis.com \
  container.googleapis.com \
  secretmanager.googleapis.com \
  dns.googleapis.com \
  certificatemanager.googleapis.com \
  --project YOUR_PROJECT
```

## Packaging (partners)

Marketplace requires `README.md` at the zip root (no wrapping folder).

```sh
./marketplace/gcp/pack.sh

gcloud storage cp marketplace/gcp/retool-blueprints-tf.zip \
  gs://retool-blueprints-tf-modules/
```
