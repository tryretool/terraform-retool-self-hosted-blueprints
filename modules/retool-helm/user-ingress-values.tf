locals {
  ingress_hosts = var.domain_name != null ? [var.domain_name, "*.${var.domain_name}"] : []

  null_user_ingress_values = {
    ingress = {
      enabled = false
    }
  }

  # When no user-ingress wiring is provided, default to a chart with no Ingress
  # so callers using their own ingress topology (e.g. an AWS ALB
  # TargetGroupBinding declared after this module) don't have to remember to
  # turn it off themselves.
  user_ingress_values = var.user_ingress == null ? [yamlencode(local.null_user_ingress_values)] : concat(

    # "external": routing is handled outside the chart (e.g. AWS Load Balancer
    # Controller TargetGroupBinding). retool-helm renders nothing — the caller
    # is responsible for any chart Ingress/HTTPRoute toggles they need.
    var.user_ingress.ingress_mode == "external" ? [yamlencode(local.null_user_ingress_values)] : [],

    # "gke-gateway-controller": disable the chart Ingress and attach a Gateway
    # API HTTPRoute to the user-ingress Gateway.
    var.user_ingress.ingress_mode == "gke-gateway-controller" ? [yamlencode({
      ingress = {
        enabled = false
      }
      httpRoute = {
        enabled   = true
        hostnames = local.ingress_hosts
        parentRefs = [{
          name        = var.user_ingress.gateway_name
          namespace   = "default"
          sectionName = var.user_ingress.gateway_section_name
        }]
      }
    })] : [],

    # "azure-agic": render a k8s Ingress for AGIC to reconcile. The
    # cert-manager.io/cluster-issuer annotation and TLS block are only added
    # when the user-ingress module provisioned a ClusterIssuer + main TLS
    # secret (HTTPS path).
    var.user_ingress.ingress_mode == "azure-agic" ? [yamlencode({
      ingress = {
        enabled          = true
        ingressClassName = var.user_ingress.ingress_class_name
        annotations = merge(
          {
            "appgw.ingress.kubernetes.io/health-probe-path"     = "/api/checkHealth"
            "appgw.ingress.kubernetes.io/health-probe-timeout"  = "10"
            "appgw.ingress.kubernetes.io/health-probe-interval" = "15"
          },
          var.user_ingress.cluster_issuer_name != null ? {
            "cert-manager.io/cluster-issuer" = var.user_ingress.cluster_issuer_name
          } : {},
        )
        hosts = [for h in local.ingress_hosts : {
          host = h
          paths = [{
            path     = "/"
            pathType = "Prefix"
          }]
        }]
        tls = var.user_ingress.tls_secret_name != null ? [{
          secretName = var.user_ingress.tls_secret_name
          hosts      = local.ingress_hosts
        }] : []
      }
    })] : [],

    # Agent sandbox proxy gets its own Ingress only under AGIC; on the other
    # modes the proxy hostname is served by the same ALB/Gateway as Retool.
    var.user_ingress.ingress_mode == "azure-agic" && var.user_ingress.agent_sandbox_proxy_enabled && var.domain_name != null ? [yamlencode({
      agentSandbox = {
        proxy = {
          ingress = {
            enabled          = true
            host             = "agent-proxy.${var.domain_name}"
            ingressClassName = var.user_ingress.ingress_class_name
            annotations = merge(
              {
                "appgw.ingress.kubernetes.io/health-probe-path"     = "/health"
                "appgw.ingress.kubernetes.io/health-probe-timeout"  = "10"
                "appgw.ingress.kubernetes.io/health-probe-interval" = "15"
                "appgw.ingress.kubernetes.io/request-timeout"       = "40"
              },
              var.user_ingress.cluster_issuer_name != null ? {
                "cert-manager.io/cluster-issuer" = var.user_ingress.cluster_issuer_name
              } : {},
            )
            tls = var.user_ingress.agent_proxy_tls_secret_name != null ? [{
              secretName = var.user_ingress.agent_proxy_tls_secret_name
              hosts      = ["agent-proxy.${var.domain_name}"]
            }] : []
          }
        }
      }
    })] : [],
  )
}
