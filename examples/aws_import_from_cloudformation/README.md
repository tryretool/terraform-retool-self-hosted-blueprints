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

## Running a migration

The step-by-step procedure lives in **[MIGRATION.md](./MIGRATION.md)** — a terse
runbook covering prerequisites, the helper, apply, verification, DNS cutover and
decommissioning. It was verified end to end against a live CloudFormation
deployment.

The rest of this document is reference material: what the example does, and the
decisions behind it.

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
