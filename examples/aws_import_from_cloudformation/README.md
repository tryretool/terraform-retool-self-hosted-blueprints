# Migrating from the CloudFormation ECS/Fargate stack to EKS

For deployments running Retool on ECS/Fargate via
[`retool-onpremise`](https://github.com/tryretool/retool-onpremise)'s
CloudFormation templates.

Unlike the [`aws_all_inclusive`](../aws_all_inclusive) examples, this stack
creates **no VPC and no databases**. It points at the ones your CloudFormation
deployment already runs — the Retool database in particular holds every app,
query, resource and user you have, and is read but never modified. What this
stack builds beside them is the EKS cluster, the supporting cluster services,
the Retool Helm release, and a new load balancer to cut over to.

Both deployments run side by side, sharing one database, until you switch DNS.
So you can validate the new one before committing to it, and roll back by
switching DNS back.

A helper script reads your CloudFormation stack and writes most of the
configuration for you.

See the [repository README](../../README.md) for general prerequisites.

## What changes, and what doesn't

| | CloudFormation (ECS) | This stack (EKS) |
| --- | --- | --- |
| VPC, subnets | stack *parameters*, not resources | **referenced as-is** |
| Retool database | created by the stack | **referenced as-is** |
| Temporal database | created by the stack | **referenced as-is** |
| Encryption key, JWT secret | created by the stack | **referenced as-is** |
| Compute | Fargate tasks per service | EKS + Karpenter, pods per service |
| Temporal cluster | 5 ECS services | Helm subchart in-cluster |
| Code executor | standalone ECS service | bundled in the chart |
| Service discovery | Cloud Map (`*.retoolsvc`) | Kubernetes Service DNS |
| Secrets delivery | `{{resolve:secretsmanager}}` at deploy | External Secrets Operator, continuously |
| Load balancer | created by the stack | **new one, created here** |

Nothing is imported into Terraform state, and nothing is taken away from
CloudFormation. The only changes this stack makes to existing resources are two
additive ones: a Karpenter discovery tag on the private subnets, and an ingress
rule on each database security group so the new EKS nodes can connect. Existing
rules are untouched, so the ECS deployment keeps its access throughout.

> [!IMPORTANT]
> The **encryption key must be carried over**. Every credential stored in the
> Retool database is encrypted with it; deploying with a fresh key leaves every
> saved resource credential undecryptable. `encryption_key_secret` is a required
> input for exactly this reason.

## Prerequisites

Beyond the repository-wide ones:

- [`uv`](https://docs.astral.sh/uv/getting-started/installation/), to run the
  helper. It resolves the helper's dependencies on first run; there is nothing
  to install.
- Credentials that can read CloudFormation, RDS, and Secrets Manager.
- Your existing private subnets need **outbound internet access** — a NAT
  gateway, or VPC endpoints for ECR and S3 plus egress to `charts.retool.com`.
  EKS nodes cannot pull images without it. If your CloudFormation stack ran its
  tasks in public subnets with `AssignPublicIp: ENABLED`, plan for this.
- Subnets in **at least two availability zones**, for both the cluster and the
  load balancer.

> [!WARNING]
> The Karpenter subnet tag this stack adds lives on a resource CloudFormation may
> consider its own. If your subnets are declared in a template that specifies
> their tags exhaustively, a later stack update can revert the tag, leaving
> Karpenter unable to find subnets. Set `manage_karpenter_subnet_tags = false`
> and apply `karpenter.sh/discovery` (valued to the EKS cluster name) from the
> template instead.

## Step 1 — look at what you have

```sh
./import_from_cloudformation.py \
  --stack-name <your-stack> --region <region> \
  describe-cf-stack
```

Read-only. It prints the stack's parameters, both databases with their
connection details and credentials secrets, the shape of each secret, and then
anything needing attention — a missing encryption key, a database with no
discoverable credentials secret, more than one Temporal candidate.

## Step 2 — generate the configuration

```sh
mv provider.example.tf provider.tf
cp vars.tf.example terraform.tfvars

./import_from_cloudformation.py \
  --stack-name <your-stack> --region <region> \
  import-tfvars --prefix retool-prod
```

> [!NOTE]
> Use `mv`, not `cp`, for the provider file. Terraform loads every `*.tf` file in
> the directory, and `provider.example.tf` matches — keeping both would declare
> each provider twice.

That writes `imported.tfvars`: everything derivable from the stack — VPC and
subnet IDs, both databases, the secret ARNs, the certificate ARN, the image tag,
replica counts, and the ALB OIDC endpoints if your stack uses them. Edit
`terraform.tfvars` for what's yours: `prefix`, `region`, `aws_profile`.

The two files layer, imported first:

```sh
terraform apply -var-file=imported.tfvars -var-file=terraform.tfvars
```

`imported.tfvars` is deliberately comment-free and safe to regenerate; keep your
own edits in `terraform.tfvars`, where they win.

**Secret shapes.** CloudFormation's `GenerateSecretString` stores JSON, nesting
the value under a key like `password`, while a bare string is more natural here.
No change is needed — Terraform reads a named property just as well, and that's
what the helper writes by default. It will *offer* to create a derived
raw-string secret instead; declining changes nothing.

## Step 3 — deploy

```sh
terraform init
terraform plan  -var-file=imported.tfvars -var-file=terraform.tfvars
terraform apply -var-file=imported.tfvars -var-file=terraform.tfvars
```

Read the plan before applying. Against your existing infrastructure it should
show **only** additive changes: the subnet tags, and one ingress rule per
database security group. No VPC, no RDS instance, and no modification to either.

Then point `kubectl` at the new cluster:

```sh
eval "$(terraform output -raw kubeconfig_command)"
kubectl get pods
```

## Step 4 — validate before cutting over

The new deployment is live on its own load balancer while the CloudFormation one
still serves your users. Its certificate is issued for `domain_name`, not for
the load balancer's own name, so send the right hostname to its address:

```sh
curl --resolve "<domain_name>:443:$(dig +short "$(terraform output -raw alb_dns_name)" | head -1)" \
  "https://<domain_name>/api/checkHealth"
```

Browse it the same way by adding that IP and `domain_name` to your hosts file.

Both deployments read and write the same database, so anything you do in one is
immediately visible in the other.

## Step 5 — cut over

Point `domain_name` at the new load balancer:

- If DNS is managed elsewhere (the usual case), update the record to
  `alb_dns_name`, or an alias to it.
- If you set `hosted_zone_id`, this stack already manages the alias records —
  nothing to do.

Watch the new deployment, and switch DNS back if anything looks wrong.

## Step 6 — decommission

Once you're confident, delete the CloudFormation stack. **Before you do**, make
sure it will not take your data with it — the databases are still
CloudFormation's:

- Set `DeletionPolicy: Retain` (or the equivalent stack policy) on the RDS
  resources and every secret this stack references, and update the stack, or
- take a final snapshot and detach the resources from the stack first.

The `RetoolRDSSecret` in the upstream template already carries
`DeletionPolicy: Retain`; the RDS instances and the encryption key secret do not.

Afterwards the databases and secrets are unmanaged — no longer CloudFormation's,
and not Terraform's either. Adopting them into Terraform is a separate exercise;
this example deliberately does not attempt it, so that nothing it does can
disturb the running deployment.

## Reference

### The helper

```
--stack-name   CloudFormation stack name        (required)
--region       AWS region                        (required)
--profile      AWS CLI profile
--chdir        Terraform working directory       (default: .)

describe-cf-stack   read-only summary of the stack
import-tfvars       write imported.tfvars        (--prefix, --output, --yes)
```

It reads the stack's parameters and resources, then traverses via the AWS APIs
to what the stack only references — RDS connection details, subnet groups,
security groups, secret shapes — and locates a Temporal database even when it
was created outside the stack, scoping the search to the Retool database's
subnet group so unrelated databases are never picked up.

The one action that writes to AWS — creating a derived raw-string secret — is
offered explicitly and never implied.

### Temporal

The CloudFormation stack ran Temporal as five ECS services. The Retool Helm chart
runs the whole Temporal cluster itself via its bundled
`retool-temporal-services-helm` subchart, so only the database carries over,
whether it's a plain RDS instance or an Aurora cluster — see `temporal.tf`. The
chart wires the frontend host automatically; the Cloud Map namespace has no
equivalent and is not ported.

Setting `temporal_db = null` disables Retool Workflows entirely.

### Edge authentication

`alb_oidc` reproduces the CloudFormation stack's `authenticate-oidc` listener
action: users complete an OIDC flow at the load balancer before any request
reaches Retool. This is separate from Retool's own authentication.

Terraform reads the client credentials to configure the listener, so they land
in Terraform state — use an encrypted, access-restricted
[backend](https://developer.hashicorp.com/terraform/language/backend).

### Sizing

The CloudFormation stack sized each ECS service with Fargate task CPU/memory.
Here, `replica_counts` sets pod counts and Karpenter provisions nodes to fit.
Resource requests and limits stay at the chart defaults; tune them with the
[scaling guide](../../guides/scaling.md) rather than transcribing Fargate task
sizes directly.

### Things that don't carry over

CloudWatch `awslogs` drivers, Container Insights, and ECS Exec are ECS-specific.
Their EKS equivalents are cluster logging and `enabled_cloudwatch_logs_exports`
on RDS, configured separately.

### Things you gain

Karpenter autoscaling, External Secrets Operator (so Secrets Manager stays the
source of truth continuously, rather than being resolved once at deploy time),
cert-manager, the AWS Load Balancer Controller, Reloader, metrics-server, and
the EBS CSI driver — all installed by the `aws-retool-services` module.
