output "registry_id" {
  description = "ID of the container registry"
  value       = azurerm_container_registry.main.id
}

output "registry_name" {
  description = "Name of the container registry"
  value       = azurerm_container_registry.main.name
}

output "registry_login_server" {
  description = "Login server of the container registry"
  value       = azurerm_container_registry.main.login_server
}

output "admin_username" {
  description = "Admin username for the container registry"
  value       = azurerm_container_registry.main.admin_username
  sensitive   = true
}

output "admin_password" {
  description = "Admin password for the container registry"
  value       = azurerm_container_registry.main.admin_password
  sensitive   = true
}

output "private_endpoint_id" {
  description = "ID of the private endpoint"
  value       = var.enable_private_endpoint ? azurerm_private_endpoint.acr[0].id : null
}

output "private_dns_zone_id" {
  description = "ID of the private DNS zone"
  value       = var.enable_private_endpoint ? azurerm_private_dns_zone.acr[0].id : null
}

output "webhook_id" {
  description = "ID of the webhook"
  value       = var.enable_webhook ? azurerm_container_registry_webhook.ci_cd[0].id : null
}

output "build_task_id" {
  description = "ID of the build task"
  value       = var.enable_build_task ? azurerm_container_registry_task.build[0].id : null
}
