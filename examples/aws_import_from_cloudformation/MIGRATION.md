# Migration runbook: Retool on ECS/Fargate → EKS

Stands up Retool on EKS beside your existing CloudFormation deployment, reusing
its VPC, database and secrets. Both run at once against the same database; the
cutover is a DNS change and the rollback is changing it back.

Nothing is imported into Terraform state and nothing is taken from
CloudFormation. The only changes to existing resources are additive:

- a `karpenter.sh/discovery` tag on each private subnet
- one Postgres ingress rule per database security group, for the EKS nodes

> [!IMPORTANT]
> **The encryption key must be carried over.** Every credential in the Retool
> database is encrypted with it; a new key makes them all undecryptable.

`import_from_cloudformation.py` is offered as a convenience for the read-only
discovery steps. It is never required — every step below gives the manual
equivalent, and the script only ever reads, except for one explicitly confirmed
secret write.

Verified end to end 2026-08-27 against Retool 4.0.9-stable on Postgres 16.14.
Steps 6–8 were not exercised; everything else was.

---

## 0. Prerequisites

Installed locally:
* `terraform` ≥ 1.11 (or `terragrunt`)
* `kubectl`
* `helm`
* `uv`
* `aws` cli

Credentials that can read CloudFormation/RDS/EC2/SecretsManager and create EKS,
IAM, ELB and Secrets Manager resources.

Network, checked against the CloudFormation stack's parameters:

- `SubnetId` → EKS nodes. Needs **NAT egress** (images come from Docker Hub and
  `charts.retool.com`) and **≥2 AZs**. If your ECS tasks run in *public*
  subnets, set `private_subnet_ids` to NAT'd private subnets instead.
- `LoadBalancerSubnetId` → the new ALB. Public, **≥2 AZs**.

## 1. Copy the example

Create a copy of this example directory, as it will serve as a Terraform module which will configure and provision all the new AWS resources.

```sh
cp -r examples/aws_import_from_cloudformation/ <working-dir>/ && cd <working-dir>
mv provider.example.tf provider.tf
```

It is also recommended to open `provider.tf` and modify it as needed to use the
appropriate AWS credentials, as well as to use a [suitable state backend such as S3](https://developer.hashicorp.com/terraform/language/backend/s3).

## 2. Read the CloudFormation stack

```sh
./import_from_cloudformation.py \
  --stack-name <stack> --region <region> --profile <profile> \
  describe-cf-stack
```

This is a read-only operation which will print out the relevant parameters and resource attributes discovered in your existing CloudFormation stack. Confirm it succeeds and contains the values you expect to be migrated over.

<details>
<summary>Manually</summary>

```sh
# Parameters — VpcId, SubnetId, LoadBalancerSubnetId, BaseDomain, RetoolImage,
# Desired*Count, and CertificateARN / AlbOAuthARN if the stack uses them
aws cloudformation describe-stacks --stack-name <stack> \
  --query 'Stacks[0].Parameters' --output table

# Resource physical IDs — databases and secrets
aws cloudformation list-stack-resources --stack-name <stack> \
  --query 'StackResourceSummaries[?ResourceType==`AWS::RDS::DBInstance`
        || ResourceType==`AWS::RDS::DBCluster`
        || ResourceType==`AWS::SecretsManager::Secret`].[LogicalResourceId,PhysicalResourceId]' \
  --output table

# Database connection details and its security group
aws rds describe-db-instances --db-instance-identifier <RetoolRDSInstance> \
  --query 'DBInstances[0].{Endpoint:Endpoint.Address,Port:Endpoint.Port,DBName:DBName,
           User:MasterUsername,SG:VpcSecurityGroups[?Status==`active`].VpcSecurityGroupId}'

# Which JSON key holds each secret's value
aws secretsmanager get-secret-value --secret-id <arn> --query SecretString --output text
```
</details>

## 3. Write the configuration

```sh
./import_from_cloudformation.py \
  --stack-name <stack> --region <region> --profile <profile> \
  import-tfvars --prefix <deployment-prefix>

cp vars.tf.example overrides.auto.tfvars
```

The command above generates a local file `imported.auto.tfvars` which will hold all
the configuration derived from the existing CF stack. It is safe to re-run as
needed. Review `imported.auto.tfvars` before applying — in particular that
`private_subnet_ids` are NAT'd private subnets (see step 0).

Review `imported.auto.tfvars` before applying, in particular that
`private_subnet_ids` are NAT'd private subnets (step 0).

Set your own values in `overrides.auto.tfvars`:

```hcl
region      = "us-west-2"
# put your local aws profile name here
aws_profile = "<profile>"

# select a name prefix that will be used to name all the new AWS resources. 
# this name should be:
# - distinct from the CF stack name
# - permanent, as it cannot be easily changed after resource provisioning
# - contain your company name, to avoid global S3 bucket name collisions
# - unique within the target AWS account
prefix      = "retool-eks"

# false only if the CF stack has no ACM cert and serves plain HTTP
enable_https = true
```

A full variable reference for this example module can be found in
[`variables.tf`](./variables.tf). Also, any additional customizations can be
made to any submodule in [`main.tf`](./main.tf) inline if you consult that
submodule's [own reference](../../modules/).

If the stack had no `CertificateARN`, `acm_certificate_arn` is absent and this
stack **creates a public Route53 hosted zone** for the domain to validate a
certificate of its own. When DNS lives elsewhere, set `hosted_zone_id` to the
existing zone or supply `acm_certificate_arn` — otherwise you get a second,
undelegated zone.

<details>
<summary>Manually</summary>

Write `imported.auto.tfvars` yourself from what step 2 printed. Everything in it
is described in `variables.tf`; a minimal file is:

```hcl
vpc_id             = "vpc-…"          # VpcId
private_subnet_ids = ["subnet-…", …]  # SubnetId (NAT'd private)
public_subnet_ids  = ["subnet-…", …]  # LoadBalancerSubnetId
domain_name        = "retool.example.com"   # BaseDomain, without scheme
retool_image_tag   = "4.0.9-stable"         # RetoolImage, tag only

retool_db = {
  instance_identifier   = "…"   # RetoolRDSInstance physical ID
  credentials_secret_id = "arn:aws:secretsmanager:…"   # RetoolRDSSecret
  password_property     = "password"
  security_group_id     = "sg-…"
}

encryption_key_secret = {
  secret_id = "arn:aws:secretsmanager:…"   # RetoolEncryptionKeySecret
  property  = "password"                    # the JSON key holding the value
}
jwt_secret = { secret_id = "arn:…", property = "password" }          # optional
license_key_secret = { secret_id = "arn:…", property = "licenseKey" } # optional
```

Add `acm_certificate_arn`, `alb_oidc` and `temporal_db` only if your stack has
them. CloudFormation's `GenerateSecretString` nests values under a key —
`property` is that key, or `null` for a bare string.
</details>

## 4. Apply

```sh
terraform init
terraform plan
terraform apply
```

> [!IMPORTANT]
> Check the plan before applying. Against existing infrastructure it must be
> **`0 to change, 0 to destroy`** — the only touches are the subnet tags and
> database ingress rules listed at the top. Anything else means a value in
> `imported.auto.tfvars` does not match reality.

A full initial apply usually takes ~30–60 min, mostly waiting on EKS cluster creation, RDS DB creation, and the Retool Helm release.

## 5. Verify the cluster

```sh
eval "$(terraform output -raw kubeconfig_command)"

kubectl get pods -n default              # all 1/1 Running
kubectl get externalsecret -n default    # all SecretSynced
```

Confirm the new deployment is on the CloudFormation database:

```sh
kubectl get deploy retool -n default \
  -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="POSTGRES_HOST")].value}'
```

Re-run `terraform plan` — it should report no changes.

Reach it through its own load balancer, sending your domain as the Host header
(its certificate is for the domain, not the load balancer's name):

```sh
ALB=$(terraform output -raw alb_dns_name)
curl --resolve "<domain>:443:$(dig +short $ALB | head -1)" \
     "https://<domain>/api/checkHealth"     # expect 200
```

## 6. Preview with real logins

Before cutting over, let yourself and any reviewers sign in to the new
deployment while the old one still serves everyone else. Two ways, depending on
how you authenticate:

**Username/password — a preview subdomain.** Point a record at the new ALB under
the existing Retool domain: if Retool runs at `myretool.acme.org`, create
`migration-preview.myretool.acme.org` as a CNAME/alias to `alb_dns_name`. Sign
in there normally. SSO will *not* work at this hostname — the identity provider
sees a domain it has no redirect configured for.

**SSO — a local hosts entry.** Point the real domain at the new ALB on your own
machine only:

```sh
echo "$(dig +short $(terraform output -raw alb_dns_name) | head -1)  myretool.acme.org" \
  | sudo tee -a /etc/hosts
```

Both deployments read and write the same database, so anything done in the
preview is immediately visible in the live deployment.

> [!IMPORTANT]
> If the CloudFormation deployment runs Retool Workflows, enable them in **one
> deployment at a time**. Both deployments poll the same Temporal task queues,
> and workflow runs may fail or behave unpredictably while both are active.
> Keep `workflows_enabled = false` on the new deployment until cutover, then
> enable it there and disable it on the old one — or accept errors during the
> overlap period.

## 7. Cut over

Point the domain at the new ALB — update the record to `alb_dns_name`, or an
alias to it. If you set `hosted_zone_id`, Terraform already manages the alias
records and there is nothing to do.

Watch the new deployment. If necessary, a rollback can be achieved by pointing
DNS back to the old ALB, as the CloudFormation deployment is untouched and still
serving.

## 8. Stop the old deployment

> [!CAUTION]
> Do **not** delete the CloudFormation stack. It still owns your database, and
> deleting it can take the database with it. Stop its containers instead and
> leave the stack in place.

Scale every ECS service to zero. This is reversible, and the fastest rollback if
something surfaces later:

```sh
CLUSTER=<ClusterName>
for svc in $(aws ecs list-services --cluster $CLUSTER --query 'serviceArns[]' --output text); do
  aws ecs update-service --cluster $CLUSTER --service "$svc" --desired-count 0
done
```

Once you are confident, delete the services and the cluster if you want the
resources gone:

```sh
for svc in $(aws ecs list-services --cluster $CLUSTER --query 'serviceArns[]' --output text); do
  aws ecs delete-service --cluster $CLUSTER --service "$svc" --force
done
aws ecs delete-cluster --cluster $CLUSTER
```

The database, secrets and VPC stay where they are, still referenced by the new
deployment. Retiring the CloudFormation stack itself is a separate exercise:
retain the RDS resources and secrets first (`DeletionPolicy: Retain`, applied
via a stack update), or take final snapshots and detach them, before any
`delete-stack`.

## 9. Afterwards

Upgrade Retool by bumping `retool_image_tag` in `overrides.auto.tfvars` and
applying:

```hcl
retool_image_tag = "4.1.0-stable"
```

```sh
terraform apply
```

The Helm chart version is pinned separately by `retool_helm_chart_version`.

---

## Notes

**Both databases often share one security group.** The Retool templates put them
behind a single `RDSSecurityGroup`; the example emits one ingress rule per
distinct (group, port) pair, so a shared group gets one rule, not two.

**Sizing.** `replica_counts` carries over the `Desired*Count` parameters;
Karpenter provisions nodes to fit. Resource requests stay at chart defaults —
tune with the [scaling guide](../../guides/scaling.md) rather than transcribing
Fargate task sizes.

**Temporal.** `workflows_enabled` (default true) and `temporal_db` are
independent. Workflows need a Temporal cluster, but not necessarily one this
stack provisions a database for.

Set `temporal_db` and the Helm chart runs Temporal in-cluster against that
database — the helper carries one over if your CloudFormation stack had one.
Leave it null and no Temporal configuration is rendered at all; point Retool at
a Temporal you run elsewhere (Temporal Cloud, an existing cluster) via the
chart's `temporal.*` values through `retool_helm_extra_values`. Set
`workflows_enabled = false` to skip Workflows entirely.

**Edge authentication.** Only if your stack has it: `alb_oidc` reproduces the
CloudFormation listener's `authenticate-oidc` action. Terraform reads the client
credentials to configure it, so they land in state — use an encrypted,
access-restricted backend.

**Not carried over.** CloudWatch `awslogs`, Container Insights and ECS Exec are
ECS-specific; the EKS equivalents are cluster logging and
`enabled_cloudwatch_logs_exports` on RDS. Cloud Map service discovery is
replaced by Kubernetes Service DNS.
