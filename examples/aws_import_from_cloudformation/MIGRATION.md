# Migration runbook: Retool on ECS/Fargate → EKS

Stands up Retool on EKS beside your existing CloudFormation deployment, reusing
its VPC, databases and secrets. Both run at once against the same database; the
cutover is a DNS change and the rollback is changing it back.

Nothing is imported into Terraform state and nothing is taken from
CloudFormation. The only changes to existing resources are additive:

- a `karpenter.sh/discovery` tag on each private subnet
- one Postgres ingress rule per database security group, for the EKS nodes

> **The encryption key must be carried over.** Every credential in the Retool
> database is encrypted with it; a new key makes them all undecryptable. The
> helper carries it across — do not override `encryption_key_secret`.

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

Network requirements, both checked against the CloudFormation stack's
parameters:

- `SubnetId` → EKS nodes. Must have **NAT egress** (images come from Docker Hub
  and `charts.retool.com`) and span **≥2 AZs**. If your ECS tasks run in public
  subnets, override `private_subnet_ids` with NAT'd private ones instead.
- `LoadBalancerSubnetId` → the new ALB. Public, **≥2 AZs**.


## 1. Copy the example

Create a copy of this example directory, as it will serve as a Terraform module which will configure and provision all the new AWS resources.

```sh
cp -r examples/aws_import_from_cloudformation/ <working-dir>/ && cd <working-dir>
mv provider.example.tf provider.tf
```

It is also recommended to open `provider.tf` and modify it as needed to use the
appropriate AWS credentials, as well as to use a [suitable state backend such as S3](https://developer.hashicorp.com/terraform/language/backend/s3).

In `main.tf`, point the module sources at the published modules:

```hcl
source  = "tryretool/self-hosted-blueprints/retool//modules/aws-eks"
version = "~> 0.4"
```

## 2. Inspect the CloudFormation stack

```sh
./import_from_cloudformation.py \
  --stack-name <stack> --region <region> --profile <profile> \
  describe-cf-stack
```

This is a read-only operation which will print out the relevant parameters and resource attributes discovered in your existing CloudFormation stack. Confirm it succeeds and contains the values you expect to be migrated over.

## 3. Generate configuration

```sh
./import_from_cloudformation.py \
  --stack-name <stack> --region <region> --profile <profile> \
  import-tfvars --prefix <deployment-prefix>

cp vars.tf.example terraform.tfvars
```

The command above generates a local file `imported.tfvars` which will hold all
the configuration derived from the existing CF stack. It is safe to re-run as
needed. Review `imported.tfvars` before applying — in particular that
`private_subnet_ids` are NAT'd private subnets (see step 0).

Put your own manual/custom configuration values in `terraform.tfvars` so it doesn't get wiped out. A minimal `terraform.tfvars` will look like the below.

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

If the stack had no `CertificateARN`, `acm_certificate_arn` will be absent and
this stack **creates a public Route53 hosted zone** for the domain in order to
mint its own certificate. When DNS lives elsewhere, set `hosted_zone_id` to the
existing zone (records are written there instead) or supply
`acm_certificate_arn` — otherwise you get a second, undelegated zone.

## 4. Apply

```sh
terraform init
terraform plan  -var-file=imported.tfvars -var-file=terraform.tfvars
terraform apply -var-file=imported.tfvars -var-file=terraform.tfvars
```

**Check the plan before applying.** Against existing infrastructure it must be
`0 to change, 0 to destroy` — the only touches are the subnet tags and database
ingress rules listed at the top. Anything else means a value in
`imported.tfvars` does not match reality.

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

## 6. Verify serving, before touching DNS

The new ALB answers on its own name while the CF one still serves users. Its
certificate is for your domain, not the load balancer's, so send the right Host:

```sh
ALB=$(terraform output -raw alb_dns_name)
curl --resolve "<domain>:443:$(dig +short $ALB | head -1)" \
     "https://<domain>/api/checkHealth"     # expect 200
```

Both deployments read and write the same database, so anything done in one is
immediately visible in the other. Confirm the CF deployment is still healthy:

```sh
aws elbv2 describe-target-health --target-group-arn <cf-stack-tg-arn> \
  --query 'TargetHealthDescriptions[].TargetHealth.State'
```

## 7. Cut over  *(not exercised in testing)*

Point the domain at the new ALB — update the record to `alb_dns_name`, or an
alias to it. If you set `hosted_zone_id`, Terraform already manages the alias
records and there is nothing to do.

Watch the new deployment. Roll back by pointing DNS back; the CF stack is
untouched and still serving.

## 8. Decommission

Delete the CloudFormation stack. The databases are still its own, so before you
do, either:

- set `DeletionPolicy: Retain` on the RDS resources and every secret this stack
  references, and update the stack, or
- take final snapshots and detach the resources first.

`RetoolRDSSecret` already carries `DeletionPolicy: Retain` in the upstream
template; the RDS instances and the encryption key secret do not.

Afterwards the databases and secrets are unmanaged — no longer CloudFormation's,
not Terraform's either. Adopting them into Terraform is a separate exercise;
this example deliberately avoids it so nothing it does can disturb the running
deployment.

---

## Notes

**Temporal.** The Helm chart runs the whole Temporal cluster in-cluster via its
`retool-temporal-services-helm` subchart, so only the database carries over —
RDS instance or Aurora cluster alike. For Aurora the helper uses the cluster
writer endpoint. `temporal_db = null` disables Workflows.

**Both databases often share one security group.** The Retool templates put them
behind a single `RDSSecurityGroup`; the example emits one ingress rule per
distinct (group, port) pair, so a shared group gets one rule, not two.

**Edge authentication.** `alb_oidc` reproduces the CF listener's
`authenticate-oidc` action. Terraform reads the client credentials to configure
it, so they land in state — use an encrypted, access-restricted backend.

**Sizing.** `replica_counts` carries over the `Desired*Count` parameters;
Karpenter provisions nodes to fit. Resource requests stay at chart defaults —
tune with the [scaling guide](../../guides/scaling.md) rather than transcribing
Fargate task sizes.

**Not carried over.** CloudWatch `awslogs`, Container Insights and ECS Exec are
ECS-specific; the EKS equivalents are cluster logging and
`enabled_cloudwatch_logs_exports` on RDS. Cloud Map service discovery is
replaced by Kubernetes Service DNS.
