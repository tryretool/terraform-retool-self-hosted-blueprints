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
# The NamedAddress spec entry claims the reserved static IP.
#
# Applied through Helm because GCP Marketplace permits neither gavinbunney/kubectl
# nor kubernetes_manifest here. See chart/Chart.yaml for why.
#
# The Gateway is its own release so it exists before the HTTPRoute that attaches
# to it, rather than leaning on how Helm happens to order unknown kinds.
resource "helm_release" "gateway" {
  name      = "${var.prefix}-gateway"
  namespace = "default"
  chart     = "${path.module}/chart"

  values = [yamlencode({
    manifests = [{
      apiVersion = "gateway.networking.k8s.io/v1"
      kind       = "Gateway"
      metadata = {
        name      = "retool"
        namespace = local.retool_namespace
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
    }]
  })]

  depends_on = [google_certificate_manager_certificate_map_entry.main]
}

# The HTTP → HTTPS redirect (equivalent to the ALB HTTP listener redirect action)
# and a custom backend health check on /api/checkHealth (equivalent to the ALB
# target group health_check block). The backend HTTPRoute for retool:3000 is
# configured via retool-helm chart values, not here.
#
# HealthCheckPolicy targets the retool Service, which the retool-helm module
# creates afterwards. GKE accepts a policy whose target doesn't exist yet.
resource "helm_release" "routes" {
  name      = "${var.prefix}-routes"
  namespace = local.retool_namespace
  chart     = "${path.module}/chart"

  values = [yamlencode({
    manifests = [
      {
        apiVersion = "gateway.networking.k8s.io/v1"
        kind       = "HTTPRoute"
        metadata = {
          name      = "retool-redirect"
        }
        spec = {
          parentRefs = [{
            name        = "retool"
            sectionName = "http"
          }]
          hostnames = [var.domain_name]
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
      },
      {
        apiVersion = "networking.gke.io/v1"
        kind       = "HealthCheckPolicy"
        metadata = {
          name      = "retool"
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
      },
    ]
  })]

  depends_on = [helm_release.gateway]
}
