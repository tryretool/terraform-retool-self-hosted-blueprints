# ---------- Application Gateway v2 + AGIC ----------
# Classic Azure L7 load balancer managed by the Application Gateway Ingress
# Controller (AGIC). AGIC watches K8s Ingress resources and reconciles them
# into AppGW listener/backend/routing configuration.
#
# Terraform creates the AppGW with placeholder config; AGIC takes over from there.
# The lifecycle block ignores AGIC-managed attributes to prevent Terraform drift.

data "azurerm_resource_group" "main" {
  name = var.resource_group_name
}

# ---------- Static Public IP ----------

resource "azurerm_public_ip" "appgw" {
  name                = "${var.prefix}-appgw-ip"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

# ---------- Application Gateway ----------

locals {
  appgw_frontend_ip_name   = "appgw-frontend-ip"
  appgw_frontend_port_name = "http"
  appgw_backend_pool_name  = "default-pool"
  appgw_http_settings_name = "default-http-settings"
  appgw_listener_name      = "default-listener"
  appgw_rule_name          = "default-rule"
}

resource "azurerm_application_gateway" "main" {
  name                = "${var.prefix}-appgw"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  sku {
    name     = "Standard_v2"
    tier     = "Standard_v2"
    capacity = 2
  }

  gateway_ip_configuration {
    name      = "appgw-ip-config"
    subnet_id = var.vnet.appgw_subnet_id
  }

  frontend_ip_configuration {
    name                 = local.appgw_frontend_ip_name
    public_ip_address_id = azurerm_public_ip.appgw.id
  }

  frontend_port {
    name = local.appgw_frontend_port_name
    port = 80
  }

  # Placeholder backend — AGIC manages the real backends from Ingress resources.
  backend_address_pool {
    name = local.appgw_backend_pool_name
  }

  backend_http_settings {
    name                  = local.appgw_http_settings_name
    cookie_based_affinity = "Disabled"
    port                  = var.retool_service_port
    protocol              = "Http"
    request_timeout       = 30
  }

  http_listener {
    name                           = local.appgw_listener_name
    frontend_ip_configuration_name = local.appgw_frontend_ip_name
    frontend_port_name             = local.appgw_frontend_port_name
    protocol                       = "Http"
  }

  request_routing_rule {
    name                       = local.appgw_rule_name
    rule_type                  = "Basic"
    http_listener_name         = local.appgw_listener_name
    backend_address_pool_name  = local.appgw_backend_pool_name
    backend_http_settings_name = local.appgw_http_settings_name
    priority                   = 100
  }

  lifecycle {
    # AGIC continuously reconciles AppGW config from Ingress resources.
    # Terraform must ignore these attributes to prevent plan drift.
    ignore_changes = [
      backend_address_pool,
      backend_http_settings,
      frontend_port,
      http_listener,
      probe,
      redirect_configuration,
      request_routing_rule,
      ssl_certificate,
      url_path_map,
    ]
  }
}

# ---------- AGIC (Helm) ----------

resource "azurerm_user_assigned_identity" "agic" {
  name                = "${var.prefix}-agic-identity"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_federated_identity_credential" "agic" {
  name                = "${var.prefix}-agic-federated"
  resource_group_name = var.resource_group_name
  parent_id           = azurerm_user_assigned_identity.agic.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = var.aks.oidc_issuer_url
  subject             = "system:serviceaccount:default:ingress-azure"
}

# AGIC needs Contributor on the AppGW to manage its configuration.
resource "azurerm_role_assignment" "agic_appgw_contributor" {
  scope                = azurerm_application_gateway.main.id
  role_definition_name = "Contributor"
  principal_id         = azurerm_user_assigned_identity.agic.principal_id
}

# AGIC needs Reader on the RG to discover resources.
resource "azurerm_role_assignment" "agic_rg_reader" {
  scope                = data.azurerm_resource_group.main.id
  role_definition_name = "Reader"
  principal_id         = azurerm_user_assigned_identity.agic.principal_id
}

# AGIC needs Network Contributor on the AppGW subnet to perform subnets/join/action.
resource "azurerm_role_assignment" "agic_subnet_network_contributor" {
  scope                = var.vnet.appgw_subnet_id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.agic.principal_id
}

resource "helm_release" "agic" {
  name       = "ingress-azure"
  repository = "oci://mcr.microsoft.com/azure-application-gateway/charts"
  chart      = "ingress-azure"
  version    = "1.9.7"
  namespace  = "default"
  wait       = true
  timeout    = 600

  values = [yamlencode({
    appgw = {
      subscriptionId = data.azurerm_subscription.current.subscription_id
      resourceGroup  = var.resource_group_name
      name           = azurerm_application_gateway.main.name
      usePrivateIP   = false
    }
    armAuth = {
      type             = "workloadIdentity"
      identityClientID = azurerm_user_assigned_identity.agic.client_id
    }
    rbac = {
      enabled = true
    }
  })]

  depends_on = [
    azurerm_role_assignment.agic_appgw_contributor,
    azurerm_role_assignment.agic_rg_reader,
    azurerm_role_assignment.agic_subnet_network_contributor,
  ]
}
