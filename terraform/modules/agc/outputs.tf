output "agc_id" {
  description = "ID of the Application Gateway for Containers"
  value       = azurerm_application_gateway_for_containers.main.id
}

output "agc_name" {
  description = "Name of the Application Gateway for Containers"
  value       = azurerm_application_gateway_for_containers.main.name
}

output "frontend_id" {
  description = "ID of the AGC frontend"
  value       = azurerm_application_gateway_for_containers_frontend.main.id
}

output "frontend_fqdn" {
  description = "FQDN of the AGC frontend"
  value       = azurerm_application_gateway_for_containers_frontend.main.fully_qualified_domain_name
}

output "association_id" {
  description = "ID of the AGC association"
  value       = azurerm_application_gateway_for_containers_association.main.id
}

output "alb_controller_identity_id" {
  description = "ID of the ALB Controller managed identity"
  value       = azurerm_user_assigned_identity.alb_controller.id
}

output "alb_controller_identity_client_id" {
  description = "Client ID of the ALB Controller managed identity"
  value       = azurerm_user_assigned_identity.alb_controller.client_id
}

output "alb_controller_identity_principal_id" {
  description = "Principal ID of the ALB Controller managed identity"
  value       = azurerm_user_assigned_identity.alb_controller.principal_id
}

output "gateway_class_name" {
  description = "Gateway class name for AGC"
  value       = "azure-alb-external"
}

output "gateway_name" {
  description = "Name of the default Gateway resource"
  value       = var.create_default_gateway ? "${var.project_name}-${var.environment}-gateway" : null
}

output "gateway_namespace" {
  description = "Namespace of the default Gateway resource"
  value       = var.create_default_gateway ? var.gateway_namespace : null
}
