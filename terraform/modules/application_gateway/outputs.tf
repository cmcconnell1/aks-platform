output "application_gateway_id" {
  description = "ID of the Application Gateway"
  value       = azurerm_application_gateway.main.id
}

output "application_gateway_name" {
  description = "Name of the Application Gateway"
  value       = azurerm_application_gateway.main.name
}

output "public_ip_address" {
  description = "Public IP address of the Application Gateway"
  value       = azurerm_public_ip.app_gateway.ip_address
}

output "public_ip_fqdn" {
  description = "FQDN of the Application Gateway public IP"
  value       = azurerm_public_ip.app_gateway.fqdn
}

output "backend_address_pool_id" {
  description = "ID of the default backend address pool"
  value       = "${azurerm_application_gateway.main.id}/backendAddressPools/defaultaddresspool"
}

output "user_assigned_identity_id" {
  description = "ID of the user assigned identity for Application Gateway"
  value       = azurerm_user_assigned_identity.app_gateway.id
}

output "user_assigned_identity_client_id" {
  description = "Client ID of the user assigned identity for Application Gateway"
  value       = azurerm_user_assigned_identity.app_gateway.client_id
}

output "user_assigned_identity_principal_id" {
  description = "Principal ID of the user assigned identity for Application Gateway"
  value       = azurerm_user_assigned_identity.app_gateway.principal_id
}

output "agic_extension_id" {
  description = "ID of the AGIC extension"
  value       = var.enable_agic ? azurerm_kubernetes_cluster_extension.agic[0].id : null
}

output "frontend_ip_configuration_id" {
  description = "ID of the frontend IP configuration"
  value       = "${azurerm_application_gateway.main.id}/frontendIPConfigurations/appGwPublicFrontendIp"
}

output "http_listener_id" {
  description = "ID of the HTTP listener"
  value       = "${azurerm_application_gateway.main.id}/httpListeners/httpListener"
}

output "https_listener_id" {
  description = "ID of the HTTPS listener"
  value       = var.ssl_certificate_name != null ? "${azurerm_application_gateway.main.id}/httpListeners/httpsListener" : null
}

# Alias for workload identity configuration
output "agic_identity_id" {
  description = "ID of the AGIC user assigned identity (alias for user_assigned_identity_id)"
  value       = azurerm_user_assigned_identity.app_gateway.id
}

output "agic_identity_client_id" {
  description = "Client ID of the AGIC user assigned identity"
  value       = azurerm_user_assigned_identity.app_gateway.client_id
}
