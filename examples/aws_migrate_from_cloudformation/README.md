# Migrating from the CloudFormation ECS/Fargate stack to EKS

For deployments running Retool on ECS/Fargate via
[`retool-onpremise`](https://github.com/tryretool/retool-onpremise)'s
CloudFormation templates, moving to Terraform + EKS.

Unlike the [`aws_all_inclusive`](../aws_all_inclusive) examples, this stack
creates **no VPC and no database**. It adopts the ones your CloudFormation stack
already runs — the RDS instance in particular holds every app, query, resource
and user in your deployment, and is read but never recreated. What this stack
builds beside them is the EKS cluster, the supporting cluster services, the
Retool Helm release, and a new load balancer to cut traffic over to.

Both deployments run side by side until you switch DNS, so you can validate the
new one before committing to it, and roll back by switching DNS back.

See the [repository README](../../README.md) for general prerequisites.

## What changes, and what doesn't

| | CloudFormation (ECS) | This stack (EKS) |
| --- | --- | --- |
| VPC, subnets | created by the stack | **adopted as-is** |
| Retool database | created by the stack | **adopted as-is** |
| Encryption key, JWT secret | created by the stack | **adopted as-is** |
| Temporal database | created by the stack | **adopted as-is** |
| Compute | Fargate tasks per service | EKS + Karpenter, pods per service |
| Temporal cluster | 5 ECS services | Helm subchart in-cluster |
| Code executor | standalone ECS service | bundled in the chart |
| Service discovery | Cloud Map (`*.retoolsvc`) | Kubernetes Service DNS |
| Secrets delivery | `{{resolve:secretsmanager}}` at deploy | External Secrets Operator, continuously |
| Load balancer | created by the stack | **new one, created here** |

> [!IMPORTANT]
> The **encryption key must be carried over**. Every credential stored in the
> Retool database is encrypted with it; deploying with a fresh key leaves every
> saved resource credential undecryptable. `encryption_key_secret` is a required
> input for exactly this reason.

## Prerequisites

Beyond the repository-wide ones:

- Your existing private subnets need **outbound internet access** — a NAT
  gateway, or VPC endpoints for ECR and S3 plus egress to `charts.retool.com`.
  EKS nodes cannot pull images without it. If your CloudFormation stack ran its
  tasks in public subnets with `AssignPublicIp: ENABLED`, plan for this.
- Subnets in **at least two availability zones**, for both the cluster and the
  load balancer.
- Permission to tag the existing subnets (this stack adds the Karpenter
  discovery tag) and to add an ingress rule to the existing database security
  groups.

> [!WARNING]
> The subnet tags and security group rules this stack adds live on
> CloudFormation-managed resources. If your subnets or security groups are
> declared in a CloudFormation template that specifies their tags or ingress
> rules exhaustively, a later stack update can revert them — which would leave
> Karpenter unable to find subnets, or Retool unable to reach its database.
> Where that's a risk, declare the equivalents in the CloudFormation template
> instead and opt out here: `manage_karpenter_subnet_tags`,
> `tag_subnets_for_load_balancer_discovery`, `db.security_group_id` and
> `temporal.security_group_id` all let you take over that piece yourself. The
> `karpenter.sh/discovery` tag value must equal the EKS cluster name.

## Step 1 — inventory the CloudFormation stack

Every input this example needs maps to a parameter or resource of your existing
stack. List the parameters:

```sh
aws cloudformation describe-stacks --stack-name <name> \
  --query 'Stacks[0].Parameters' --output table
```

and the resources you'll reference by ID:

```sh
aws cloudformation describe-stack-resources --stack-name <name> \
  --query 'StackResources[?ResourceType==`AWS::SecretsManager::Secret` ||
                           ResourceType==`AWS::RDS::DBInstance` ||
                           ResourceType==`AWS::RDS::DBCluster` ||
                           ResourceType==`AWS::EC2::SecurityGroup`].
           [LogicalResourceId,PhysicalResourceId]' --output table
```

| This example | CloudFormation |
| --- | --- |
| `vpc_id`, `private_subnet_ids`, `public_subnet_ids` | `VpcId`, `SubnetId`, `LoadBalancerSubnetId` |
| `db.instance_identifier`, `db.credentials_secret_id` | `RetoolRDSInstance`, `RetoolRDSSecret` |
| `encryption_key_secret` | `RetoolEncryptionKeySecret` |
| `jwt_secret` | `RetoolJWTSecret` |
| `license_key_secret` | `LicenseKeyARN` |
| `acm_certificate_arn` | `CertificateARN` |
| `domain_name` | `BaseDomain`, minus the scheme |
| `temporal.*` | `RetoolTemporalRDSCluster`, `RetoolTemporalRDSSecret`, `TemporalImage` |
| `retool_image_tag` | `RetoolImage`, tag only |
| `replica_counts` | `DesiredCount`, `DesiredWorkflowsCount`, `DesiredCodeExecutorCount` |
| `usage_api_token`, `ldap_role_mapping` | `UsageAPIToken`, `LDAPRoleMapping` |
| `alb_oidc` | `ALBListener2`'s `authenticate-oidc` action, `AlbOAuthARN`, `FederateEnvironment` |

Secrets created by CloudFormation's `GenerateSecretString` are JSON objects, not
bare strings — hence the `property` field on each secret input (`password` for
most, `licenseKey` for the license). The defaults already match the templates.

## Step 2 — configure

```sh
mv provider.example.tf provider.tf
cp vars.tf.example terraform.tfvars
```

> [!NOTE]
> Use `mv`, not `cp`, for the provider file. Terraform loads every `*.tf` file in
> the directory, and `provider.example.tf` matches — keeping both would declare
> each provider twice.

Then edit `terraform.tfvars`. `variables.tf` documents every input in full.

Pick a `prefix` distinct from your CloudFormation stack name: it names the EKS
cluster and the `retool/<prefix>/*` Secrets Manager namespace, and the two
deployments coexist for the duration of the migration.

## Step 3 — deploy

```sh
aws sso login --profile <your-profile>   # or otherwise authenticate
terraform init
terraform plan
terraform apply
```

Read the plan before applying. Against the existing infrastructure it should
show **only** additive changes: subnet tags, and one ingress rule per database
security group. No VPC, no RDS instance, and no changes to either.

Then point `kubectl` at the new cluster:

```sh
eval "$(terraform output -raw kubeconfig_command)"
kubectl get pods
```

## Step 4 — validate before cutting over

The new deployment is live on its own load balancer while the CloudFormation one
still serves your users. Reach it directly:

```sh
terraform output -raw alb_dns_name
```

Requesting that hostname over HTTPS fails certificate validation — the
certificate is issued for `domain_name`, not for the load balancer's name. Send
the right hostname to the new load balancer's address instead:

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
sure it will not take your data with it:

- Set `DeletionPolicy: Retain` (or the equivalent stack policy) on the RDS
  instance and every secret this stack references, or
- take a final snapshot and detach the resources from the stack first.

The `RetoolRDSSecret` in the upstream template already carries
`DeletionPolicy: Retain`; the RDS instance and the encryption key secret do not.

## Notes on specific features

### Temporal

The CloudFormation stack ran Temporal as five ECS services against a dedicated
Aurora cluster. The Retool Helm chart runs the whole Temporal cluster itself via
its bundled `retool-temporal-services-helm` subchart, so only the database is
carried over — see `temporal.tf`. The chart wires the frontend host
automatically; the Cloud Map namespace has no equivalent and is not ported.

Omitting `temporal` disables Retool Workflows entirely.

### Edge authentication

`alb_oidc` reproduces the CloudFormation stack's `authenticate-oidc` listener
action: users complete an OIDC flow at the load balancer before any request
reaches Retool. This is separate from Retool's own authentication.

Terraform reads the client credentials to configure the listener, so they land
in Terraform state — use an encrypted, access-restricted
[backend](https://developer.hashicorp.com/terraform/language/backend).

### CloudAuth

`cloudauth` is Amazon-internal and does not apply to a standard Retool install.
It creates the PrivateLink endpoint, private hosted zone, and IAM role that the
CloudFormation stack's CloudAuth resources provided, and binds the role to the
Retool pods with an EKS Pod Identity association. See `cloudauth.tf`.

### Sizing

The CloudFormation stack sized each ECS service with Fargate task CPU/memory.
Here, `replica_counts` sets pod counts and Karpenter provisions nodes to fit.
Resource requests and limits stay at the chart defaults; tune them with the
[scaling guide](../../guides/scaling.md) rather than transcribing Fargate task
sizes directly.

### Things the CloudFormation stack had that don't carry over

CloudWatch `awslogs` drivers, Container Insights, and ECS Exec are ECS-specific.
Their EKS equivalents are cluster logging and `enabled_cloudwatch_logs_exports`
on RDS, configured separately.

### Things you gain

Karpenter autoscaling, External Secrets Operator (so Secrets Manager stays the
source of truth continuously, rather than being resolved once at deploy time),
cert-manager, the AWS Load Balancer Controller, Reloader, metrics-server, and
the EBS CSI driver — all installed by the `aws-retool-services` module.
