# Retool application configuration carried over from the CloudFormation stack.
#
# The CloudFormation stack expressed sizing as Fargate task CPU/memory per ECS
# service; here it becomes replica counts plus Kubernetes resource requests and
# limits, with Karpenter provisioning nodes to fit. The numbers below are the
# chart defaults for everything except replica counts — start here, then tune
# using guides/scaling.md rather than transcribing Fargate task sizes directly.

locals {
  # Plain (non-secret) environment variables the CloudFormation stack surfaced
  # as parameters. Anything sensitive is better placed in the
  # retool/{prefix}/extra-env-vars secret, which External Secrets Operator syncs
  # into the pods without passing through Terraform state.
  app_env = merge(
    var.usage_api_token != null ? { USAGE_API_TOKEN = var.usage_api_token } : {},
    var.ldap_role_mapping != null ? { LDAP_ROLE_MAPPING = var.ldap_role_mapping } : {},
  )

  app_values = [yamlencode({
    image = {
      tag = var.retool_image_tag
    }

    env = local.app_env

    # The jobs runner has no replica knob — the chart runs exactly one, where
    # the CloudFormation stack ran it as its own ECS service.
    replicaCount = var.replica_counts.backend

    workflows = {
      backend = {
        replicaCount = var.replica_counts.workflows_backend
      }
      worker = {
        replicaCount = var.replica_counts.workflows_worker
      }
    }

    codeExecutor = {
      replicaCount = var.replica_counts.code_executor
    }

    # Keeps at least one backend pod serving during rollouts and node
    # consolidation, matching the CloudFormation deployment configuration's
    # MinimumHealthyPercent.
    podDisruptionBudget = {
      maxUnavailable = 1
    }
  })]
}
