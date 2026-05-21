# --- Agent Sandbox Proxy backend policies (gated on enable_agent_sandbox_proxy) ---

# The GKE Gateway controller defaults to health-checking on `/`, but the agent
# sandbox proxy returns 404 there — it uses `/health` instead.
resource "kubectl_manifest" "health_check_policy_agent_sandbox_proxy" {
  count = var.enable_agent_sandbox_proxy ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "networking.gke.io/v1"
    kind       = "HealthCheckPolicy"
    metadata = {
      name      = var.agent_sandbox_proxy_service_name
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
            requestPath = "/health"
            port        = var.agent_sandbox_proxy_port
          }
        }
      }
      targetRef = {
        group = ""
        kind  = "Service"
        name  = var.agent_sandbox_proxy_service_name
      }
    }
  })
}

# The proxy handles WebSocket connections which are long-lived. Without an
# extended timeout the GCP load balancer drops idle connections after 30s.
resource "kubectl_manifest" "backend_policy_agent_sandbox_proxy" {
  count = var.enable_agent_sandbox_proxy ? 1 : 0

  yaml_body = yamlencode({
    apiVersion = "networking.gke.io/v1"
    kind       = "GCPBackendPolicy"
    metadata = {
      name      = var.agent_sandbox_proxy_service_name
      namespace = "default"
    }
    spec = {
      default = {
        timeoutSec = 60
      }
      targetRef = {
        group = ""
        kind  = "Service"
        name  = var.agent_sandbox_proxy_service_name
      }
    }
  })
}
