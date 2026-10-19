# cert-manager resources are not listed: they were already counted (var.enable_https)
# before this change, so their addresses are unchanged.

# from v0.3.0
moved {
  from = azurerm_public_ip.appgw
  to   = azurerm_public_ip.appgw[0]
}

# from v0.3.0
moved {
  from = azurerm_application_gateway.main
  to   = azurerm_application_gateway.main[0]
}

# from v0.3.0
moved {
  from = azurerm_user_assigned_identity.agic
  to   = azurerm_user_assigned_identity.agic[0]
}

# from v0.3.0
moved {
  from = azurerm_federated_identity_credential.agic
  to   = azurerm_federated_identity_credential.agic[0]
}

# from v0.3.0
moved {
  from = azurerm_role_assignment.agic_appgw_contributor
  to   = azurerm_role_assignment.agic_appgw_contributor[0]
}

# from v0.3.0
moved {
  from = azurerm_role_assignment.agic_rg_reader
  to   = azurerm_role_assignment.agic_rg_reader[0]
}

# from v0.3.0
moved {
  from = azurerm_role_assignment.agic_subnet_network_contributor
  to   = azurerm_role_assignment.agic_subnet_network_contributor[0]
}

# from v0.3.0
moved {
  from = helm_release.agic
  to   = helm_release.agic[0]
}

# from v0.3.0
moved {
  from = azurerm_dns_a_record.main
  to   = azurerm_dns_a_record.main[0]
}

# from v0.3.0
moved {
  from = azurerm_dns_a_record.wildcard
  to   = azurerm_dns_a_record.wildcard[0]
}
