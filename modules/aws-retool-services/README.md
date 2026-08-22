## `aws-retool-services` module

This is a Terraform module providing the per-deployment supporting services and configurations recommended for running Retool self-hosted in EKS. Everything it creates belongs to one Retool deployment, so it can be instantiated several times against a single cluster.

* Creates the `<prefix>-retool` namespace the Retool deployment lives in, and exports its name so `retool-helm` and `aws-user-ingress` use the same one
* Provisions the Retool secrets in AWS Secrets Manager — encryption key, JWT secret, extra env vars, and optionally the license key and the agent sandbox bundle — using write-only values so their contents never reach Terraform state
* Creates the `<prefix>-eso` IAM role granting read access to just this deployment's secrets, which the cluster's shared External Secrets Operator assumes
* Installs a namespaced ESO `SecretStore` and the `ExternalSecret` resources for the required Retool secrets, so AWS Secrets Manager remains the source of truth
* Optionally creates an S3 bucket and credentials for use as the git storage backend for Retool apps

The cluster-wide operators — the External Secrets Operator, cert-manager, the AWS Load Balancer Controller, reloader and metrics-server — are cluster singletons installed once per cluster by [`aws-eks`](../aws-eks), not by this module.

### Reusing secrets from an existing deployment

By default this module generates the encryption key and JWT secret itself. When
migrating an existing Retool deployment you must **reuse its encryption key** —
credentials stored in the Retool database are encrypted with it, and a new key
makes them undecryptable. Point the module at the existing secrets instead:

| Variable | Purpose |
| --- | --- |
| `encryption_key_secret_name` | Existing secret to use as the encryption key (no key is generated). |
| `jwt_secret_secret_path` | Existing secret to use as the JWT secret (no secret is generated). Reusing it keeps existing user sessions valid. |
| `license_key_secret_path` | Existing secret holding the license key. |

Secrets this module creates hold a bare string. Secrets created by other tooling
are often JSON objects — a CloudFormation `GenerateSecretString` secret, for
instance, nests the value under `password`. Use the matching property variable
(`encryption_key_secret_property`, `jwt_secret_secret_property`,
`license_key_secret_property`, `db_password_secret_property`) to extract a single
field rather than syncing the whole JSON blob into the Kubernetes Secret.

If you author your own `ExternalSecret` manifests that read secrets outside the
`retool/{prefix}/*` namespace — credentials for a second database, say — list
those ARNs in `extra_secret_read_arns` so ESO's IAM role can read them.

> [!NOTE] This module is intended to be used in conjunction with the other AWS-specific modules in [`retool-self-hosted-blueprints`](https://github.com/tryretool/retool-self-hosted-blueprints). See the [usage examples](https://github.com/tryretool/retool-self-hosted-blueprints/tree/main/examples) for references on how to use this module.
