# Reserved static global IP. The Gateway claims it by name so the address is
# stable across LB reprovisioning. external-dns creates the A record pointing here.
resource "google_compute_global_address" "main" {
  depends_on = [google_project_service.compute]

  name    = "${var.prefix}-ip"
  project = var.project_id
  labels  = local.all_labels
}

# Gateway — the GKE Gateway controller provisions the GCP External HTTPS LB in
# response to this resource. Equivalent to aws_lb + its two listeners.
#
# The cert map is referenced in both the metadata annotation (legacy GKE path) and
# in tls.options (required by the Gateway API CEL validation rule that mandates
# certificateRefs OR options when mode is Terminate).
# The NamedAddress spec entry claims the reserved static IP.
resource "kubectl_manifest" "gateway" {
  yaml_body = yamlencode({
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "Gateway"
    metadata = {
      name      = "retool"
      namespace = "default"
      annotations = {
        "networking.gke.io/certmap" = google_certificate_manager_certificate_map.main.name
      }
    }
    spec = {
      gatewayClassName = "gke-l7-global-external-managed"
      addresses = [{
        type  = "NamedAddress"
        value = google_compute_global_address.main.name
      }]
      listeners = [
        {
          name          = "https"
          port          = 443
          protocol      = "HTTPS"
          allowedRoutes = { namespaces = { from = "Same" } }
          # No tls block: GKE infers TLS termination from the networking.gke.io/certmap
          # annotation on the Gateway metadata. Omitting tls entirely avoids the Gateway
          # API CEL rule that would require certificateRefs or options under mode=Terminate,
          # and avoids the GWCER105 "invalid TLS option key" error from the GKE controller.
        },
        {
          name          = "http"
          port          = 80
          protocol      = "HTTP"
          allowedRoutes = { namespaces = { from = "Same" } }
        }
      ]
    }
  })

  depends_on = [google_certificate_manager_certificate_map_entry.main]
}

# HTTP → HTTPS redirect. Equivalent to the ALB HTTP listener redirect action.
# The backend HTTPRoute (retool:3000) is configured via retool-helm chart values.
resource "kubectl_manifest" "httproute_redirect" {
  yaml_body = yamlencode({
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "HTTPRoute"
    metadata = {
      name      = "retool-redirect"
      namespace = "default"
    }
    spec = {
      parentRefs = [{
        name        = "retool"
        sectionName = "http"
      }]
      hostnames = [var.base_domain]
      rules = [{
        filters = [{
          type = "RequestRedirect"
          requestRedirect = {
            scheme     = "https"
            statusCode = 301
          }
        }]
      }]
    }
  })

  depends_on = [kubectl_manifest.gateway]
}

# Custom backend health check targeting /api/checkHealth.
# Equivalent to the ALB target group health_check block.
# Attaches to the retool K8s Service by targetRef.
resource "kubectl_manifest" "health_check_policy" {
  yaml_body = yamlencode({
    apiVersion = "networking.gke.io/v1"
    kind       = "HealthCheckPolicy"
    metadata = {
      name      = "retool"
      namespace = "default"
    }
    spec = {
      default = {
        checkIntervalSec   = 15
        healthyThreshold   = 1
        unhealthyThreshold = 2
        config = {
          type = "HTTP"
          httpHealthCheck = {
            requestPath = "/api/checkHealth"
            port        = 3000
          }
        }
      }
      targetRef = {
        group = ""
        kind  = "Service"
        name  = "retool"
      }
    }
  })
}
