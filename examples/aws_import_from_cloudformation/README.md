# Importing the CloudFormation ECS/Fargate deployment's databases into Terraform

For deployments running Retool on ECS/Fargate via
[`retool-onpremise`](https://github.com/tryretool/retool-onpremise)'s
CloudFormation templates, moving to Terraform + EKS **and taking the databases
with them**.

This is the second of two migration paths:

| | [`aws_migrate_from_cloudformation`](../aws_migrate_from_cloudformation) | **this example** |
| --- | --- | --- |
| Retool & Temporal databases | stay CloudFormation-managed; Terraform only reads them | **imported into Terraform state** |
| Deleting the CloudFormation stack | must retain the databases first | the databases are already Terraform's |
| Setup | fill in `terraform.tfvars` by hand | a helper discovers everything and performs the imports |

Both run the new deployment alongside the old one and cut over by moving DNS.
Pick this one if you want CloudFormation gone entirely; pick the other if you
want the smallest possible change.

## What is and isn't imported

**Imported:** both RDS instances, their DB subnet groups, their security groups,
and every rule on those security groups.

**Not imported:**

- **The VPC and subnets.** In these templates `VpcId` and `SubnetId` are stack
  *parameters*, not stack resources — the network was never
  CloudFormation-managed, so there is nothing to reclaim. It stays referenced by
  ID, exactly as in the other example.
- **The load balancer.** This stack creates its own and runs it alongside the
  old one; moving DNS between them is the cutover, and is what makes rollback a
  DNS change rather than a rebuild.
- **The Retool secrets.** Referenced in place. Terraform reads them, so nothing
  is duplicated, but their lifecycle stays outside this stack.

## Two things that would otherwise break the running deployment

Both are handled by this example; they're described here because they explain
why the configuration looks the way it does, and because they matter if you
adapt it.

### The master password

The `aws-database` module normally has **RDS manage the master password** in
Secrets Manager. Applied to an imported database whose password came from
CloudFormation, RDS would generate a **new** password — and the running ECS
tasks, still reading the old `RetoolRDSSecret`, would lose access to the
database immediately.

So `main.tf` sets `manage_master_user_password = false` and points
`master_user_secret_arn` at the CloudFormation secret. The password does not
change, and both deployments keep working. Handing the password to RDS is
something you can do later, once ECS is gone.

### Names are fixed at creation

A security group's name and a DB subnet group's name cannot be changed in place.
The module normally generates them from the deployment prefix; if that doesn't
match the imported resource's actual name, Terraform **destroys and recreates**
it — and recreating a security group drops every rule on it, cutting ECS off.

So `security_group_name` and `db_subnet_group_name` are pinned to the real
names. The helper discovers them; don't hand-edit them.

Relatedly, the module is told **not** to manage rules on those groups
(`manage_security_group_rules = false`), because it would delete every rule it
didn't know about. Every existing rule is instead declared in
`imported-db-rules.tf` and imported individually — see [Security group
rules](#security-group-rules) below.

## Prerequisites

Beyond the [repository-wide](../../README.md) ones:

- [`uv`](https://docs.astral.sh/uv/getting-started/installation/), to run the
  helper. It resolves the helper's dependencies on first run; there is nothing
  to install.
- Credentials that can read CloudFormation, RDS, EC2, and Secrets Manager, and
  that can `terraform import`.
- Your existing private subnets need **outbound internet access** — a NAT
  gateway, or VPC endpoints for ECR and S3 plus egress to `charts.retool.com`.
  EKS nodes cannot pull images without it.
- Subnets in **at least two availability zones**, for both the cluster and the
  load balancer.

> [!WARNING]
> The subnet tags this stack adds live on resources CloudFormation may consider
> its own. If your subnets are declared in a template that specifies their tags
> exhaustively, a later stack update can revert them, leaving Karpenter unable
> to find subnets. Set `manage_karpenter_subnet_tags = false` and apply the
> `karpenter.sh/discovery` tag (valued to the EKS cluster name) from the
> template instead.

## Step 1 — look at what you have

```sh
./import_from_cloudformation.py \
  --stack-name <your-stack> --region <region> \
  describe-cf-stack
```

This is read-only. It prints the stack's parameters, both databases with
everything import cares about, every security group rule that will be preserved,
the shape of each secret, and the CloudAuth mappings — then a list of anything
that blocks a clean import.

Read the **Master password** row for each database. It should say
`self-managed (Secrets Manager)`. If it says `RDS-managed`, this example's
configuration doesn't match your deployment; stop and reconsider.

If the Temporal database is an **Aurora cluster**, it's reported as one. Aurora
cannot be imported into `aws-database`, which builds a standalone RDS instance —
the helper writes `temporal_db_mode = "external"` instead, leaving it in place
and connecting Retool to it. Everything else still imports.

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

That writes `imported.tfvars`: everything derivable from the stack. Edit
`terraform.tfvars` for what's yours — `prefix`, `region`, `aws_profile`. The two
files layer, imported first:

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

## Step 3 — stand up the cluster

```sh
terraform init
terraform plan  -var-file=imported.tfvars -var-file=terraform.tfvars
terraform apply -var-file=imported.tfvars -var-file=terraform.tfvars
```

The first plan will show the databases being **created**, because they aren't in
state yet. That's expected and is what the next step fixes — but it means you
should **import before applying**, not after. If you'd rather build the cluster
first, apply with `-target=module.eks` and come back.

## Step 4 — import

Dry run first. This is the default; the command is read-only without `--apply`:

```sh
./import_from_cloudformation.py \
  --stack-name <your-stack> --region <region> \
  import-state
```

It prints every import as a source/target pair — the AWS resource, its ID, and
the Terraform address it lands at. Nothing is executed. When it looks right:

```sh
./import_from_cloudformation.py \
  --stack-name <your-stack> --region <region> \
  import-state --apply
```

Addresses already in state are skipped, so this is re-runnable after a failure.

## Step 5 — the acceptance test

```sh
terraform plan -var-file=imported.tfvars -var-file=terraform.tfvars
```

This plan is the real check. It must show **no replacement and no deletion** of:

- either RDS instance,
- either DB subnet group,
- either security group,
- any preserved security group rule.

and **no change to master password management**. Additions are fine — the EKS
cluster, the new load balancer, the EKS-node ingress rule. A replacement or a
deletion means a value in `imported.tfvars` doesn't match reality; fix that
rather than applying.

Once it's clean, apply, then point `kubectl` at the cluster:

```sh
eval "$(terraform output -raw kubeconfig_command)"
kubectl get pods
```

## Step 6 — validate, then cut over

Both deployments now read and write the same database, so anything you do in one
is immediately visible in the other. Reach the new one directly — its
certificate is issued for `domain_name`, not for the load balancer's own name,
so send the right hostname to its address:

```sh
curl --resolve "<domain_name>:443:$(dig +short "$(terraform output -raw alb_dns_name)" | head -1)" \
  "https://<domain_name>/api/checkHealth"
```

Browse it the same way by adding that IP and `domain_name` to your hosts file.

When you're satisfied, point `domain_name` at `alb_dns_name`. Switch it back if
anything looks wrong.

## Step 7 — decommission

Delete the CloudFormation stack. The databases are Terraform's now, so they
won't go with it — but check first:

- The instances and subnet groups are in Terraform state (`terraform state list`).
- CloudFormation no longer believes it owns them. Deleting a stack whose
  template still declares an RDS instance will attempt to delete that instance
  regardless of what Terraform thinks. **Set `DeletionPolicy: Retain` on the
  database resources and update the stack before deleting it**, or remove them
  from the template first.

Then clean up the rules that only existed for ECS: delete their entries from
`retool_db_preserved_ingress_rules` in `imported.tfvars` and apply. Terraform
removes exactly those rules, leaving the EKS-node access this stack manages.

## Reference

### Security group rules

`imported-db-rules.tf` declares every pre-existing rule as its own
`aws_vpc_security_group_ingress_rule` / `egress_rule`, keyed by the rule's AWS ID
(`sgr-…`), which is also its import ID.

That's deliberate. The older `aws_security_group_rule` — which the security-group
module inside `aws-database` uses — is addressed by list index and imported by a
constructed composite ID that's ambiguous for all-traffic rules. Keying on the
AWS rule ID removes both problems, and gives each rule an independent lifecycle:
delete one entry, Terraform removes one rule.

### The helper

```
--stack-name   CloudFormation stack name        (required)
--region       AWS region                        (required)
--profile      AWS CLI profile
--chdir        Terraform working directory       (default: .)

describe-cf-stack   read-only summary and readiness check
import-tfvars       write imported.tfvars        (--prefix, --output, --yes)
import-state        terraform import             (--apply to execute)
```

It reads the stack's parameters, resources, and template `Mappings`, then
traverses via the AWS APIs to what the stack only references — RDS attributes,
subnet groups, security group rules, secret shapes — and locates a Temporal
database even when it was created outside the stack. Import operations are
modelled as explicit source/target pairs, so the dry-run output is the same list
that executes.

### Things that don't carry over

CloudWatch `awslogs` drivers, Container Insights, and ECS Exec are ECS-specific.
Their EKS equivalents are cluster logging and `enabled_cloudwatch_logs_exports`
on RDS, configured separately. Cloud Map service discovery is replaced by
Kubernetes Service DNS.

### Things you gain

Karpenter autoscaling, External Secrets Operator (so Secrets Manager stays the
source of truth continuously, rather than being resolved once at deploy time),
cert-manager, the AWS Load Balancer Controller, Reloader, metrics-server, and
the EBS CSI driver — all installed by the `aws-retool-services` module.
