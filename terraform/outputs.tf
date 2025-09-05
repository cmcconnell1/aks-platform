# Resource Group outputs
output "resource_group_name" {
  description = "Name of the resource group"
  value       = azurerm_resource_group.main.name
}

output "resource_group_location" {
  description = "Location of the resource group"
  value       = azurerm_resource_group.main.location
}

# Networking outputs
output "vnet_id" {
  description = "ID of the virtual network"
  value       = module.networking.vnet_id
}

output "aks_subnet_id" {
  description = "ID of the AKS subnet"
  value       = module.networking.aks_subnet_id
}

# AKS outputs
output "aks_cluster_name" {
  description = "Name of the AKS cluster"
  value       = module.aks.cluster_name
}

output "aks_cluster_id" {
  description = "ID of the AKS cluster"
  value       = module.aks.cluster_id
}

output "aks_fqdn" {
  description = "FQDN of the AKS cluster"
  value       = module.aks.fqdn
}

output "aks_node_resource_group" {
  description = "Resource group containing AKS nodes"
  value       = module.aks.node_resource_group
}

# Kubernetes configuration
output "kube_config_raw" {
  description = "Raw kubeconfig for the AKS cluster"
  value       = module.aks.kube_config_raw
  sensitive   = true
}

output "cluster_ca_certificate" {
  description = "Base64 encoded cluster CA certificate"
  value       = module.aks.cluster_ca_certificate
  sensitive   = true
}

output "client_certificate" {
  description = "Base64 encoded client certificate"
  value       = module.aks.client_certificate
  sensitive   = true
}

output "client_key" {
  description = "Base64 encoded client key"
  value       = module.aks.client_key
  sensitive   = true
}

output "host" {
  description = "Kubernetes API server endpoint"
  value       = module.aks.host
  sensitive   = true
}

# Container Registry outputs
output "container_registry_name" {
  description = "Name of the container registry"
  value       = module.container_registry.registry_name
}

output "container_registry_login_server" {
  description = "Login server of the container registry"
  value       = module.container_registry.registry_login_server
}

# Application Gateway outputs
output "application_gateway_public_ip" {
  description = "Public IP address of the Application Gateway"
  value       = var.enable_application_gateway ? module.application_gateway[0].public_ip_address : null
}

output "application_gateway_fqdn" {
  description = "FQDN of the Application Gateway"
  value       = var.enable_application_gateway ? module.application_gateway[0].public_ip_fqdn : null
}

# Security outputs
output "key_vault_name" {
  description = "Name of the Key Vault"
  value       = module.security.key_vault_name
}

output "key_vault_uri" {
  description = "URI of the Key Vault"
  value       = module.security.key_vault_uri
}

output "user_assigned_identity_id" {
  description = "ID of the user assigned managed identity"
  value       = module.security.user_assigned_identity_id
}

output "user_assigned_identity_client_id" {
  description = "Client ID of the user assigned managed identity"
  value       = module.security.user_assigned_identity_client_id
}

# ArgoCD outputs (conditional)
output "argocd_server_url" {
  description = "ArgoCD server URL"
  value       = var.enable_argocd ? module.gitops[0].argocd_server_url : null
}

output "argocd_admin_password" {
  description = "ArgoCD admin password"
  value       = var.enable_argocd ? module.gitops[0].argocd_admin_password : null
  sensitive   = true
}

# AI Tools outputs (conditional)
output "jupyter_hub_url" {
  description = "JupyterHub URL"
  value       = var.enable_ai_tools && var.enable_jupyter_hub ? module.ai_tools[0].jupyter_hub_url : null
}

output "mlflow_url" {
  description = "MLflow URL"
  value       = var.enable_ai_tools && var.enable_mlflow ? module.ai_tools[0].mlflow_url : null
}

# Monitoring outputs (conditional)
output "grafana_url" {
  description = "Grafana dashboard URL"
  value       = var.enable_monitoring ? module.monitoring[0].grafana_url : null
}

output "prometheus_url" {
  description = "Prometheus URL"
  value       = var.enable_monitoring ? module.monitoring[0].prometheus_url : null
}

# Connection commands
output "kubectl_config_command" {
  description = "Command to configure kubectl"
  value       = "az aks get-credentials --resource-group ${azurerm_resource_group.main.name} --name ${module.aks.cluster_name}"
}

output "docker_login_command" {
  description = "Command to login to container registry"
  value       = "az acr login --name ${module.container_registry.registry_name}"
}
