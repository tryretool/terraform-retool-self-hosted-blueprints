module "retool" {
  source = "../../modules/retool-helm"

  retool_helm_name             = local.helm_release_name
  retool_helm_chart            = var.helm_chart_name
  retool_helm_chart_repository = local.helm_chart_repository
  retool_helm_chart_version    = var.helm_chart_version

  db              = module.db-main.outputs
  retool_services = module.retool-services.outputs
  user_ingress    = module.user-ingress.outputs
  domain_name     = var.domain_name

  retool_helm_extra_values = [yamlencode({
    image = {
      repository = var.image_repo
      tag        = var.image_tag
    }
    codeExecutor = {
      image = {
        repository = var.code_executor_image_repo
        tag        = var.code_executor_image_tag
      }
    }
    rr = {
      jsExecutor = {
        image = {
          repository = var.js_executor_image_repo
          tag        = var.js_executor_image_tag
        }
      }
      agentSandbox = {
        image = {
          repository = var.agent_sandbox_image_repo
          tag        = var.agent_sandbox_image_tag
        }
        initImage = {
          repository = var.busybox_image_repo
          tag        = var.busybox_image_tag
        }
        devicePlugin = {
          image = {
            repository = var.smarter_device_manager_image_repo
            tag        = var.smarter_device_manager_image_tag
          }
        }
      }
    }
    telemetry = {
      image = {
        repository = var.telemetry_image_repo
        tag        = var.telemetry_image_tag
      }
    }
  })]

  depends_on = [module.gke, module.retool-services, module.user-ingress]
}
