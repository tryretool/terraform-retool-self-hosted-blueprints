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
            # AGIC Ingress doesn't like having multiple host: rules in a single
            # Ingress, but it's fine adding hostname aliases this way
            "appgw.ingress.kubernetes.io/hostname-extension" = "*.${var.domain_name}"
            # AGIC is dumb and needs to be explicitly told what order in which
            # to evaluate rules/listeners. Set this to arbitrary value of 1000
            # so that, if any other ingress is enabled, it can use a lower
            # value like 900 so it gets evaluated before the wildcard here.
            "appgw.ingress.kubernetes.io/rule-priority" = "1000"
          },
          var.user_ingress.cluster_issuer_name != null ? {
            "cert-manager.io/cluster-issuer" = var.user_ingress.cluster_issuer_name
          } : {},
        )
        hosts = [{
          host = var.domain_name
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
  )
}
