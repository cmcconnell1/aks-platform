output "cluster_id" {
  description = "ID of the AKS cluster"
  value       = azurerm_kubernetes_cluster.main.id
}

output "cluster_name" {
  description = "Name of the AKS cluster"
  value       = azurerm_kubernetes_cluster.main.name
}

output "fqdn" {
  description = "FQDN of the AKS cluster"
  value       = azurerm_kubernetes_cluster.main.fqdn
}

output "private_fqdn" {
  description = "Private FQDN of the AKS cluster"
  value       = azurerm_kubernetes_cluster.main.private_fqdn
}

output "node_resource_group" {
  description = "Resource group containing AKS nodes"
  value       = azurerm_kubernetes_cluster.main.node_resource_group
}

output "kube_config" {
  description = "Kubernetes configuration"
  value       = azurerm_kubernetes_cluster.main.kube_config
  sensitive   = true
}

output "kube_config_raw" {
  description = "Raw kubeconfig for the AKS cluster"
  value       = azurerm_kubernetes_cluster.main.kube_config_raw
  sensitive   = true
}

output "cluster_ca_certificate" {
  description = "Base64 encoded cluster CA certificate"
  value       = azurerm_kubernetes_cluster.main.kube_config.0.cluster_ca_certificate
  sensitive   = true
}

output "client_certificate" {
  description = "Base64 encoded client certificate"
  value       = azurerm_kubernetes_cluster.main.kube_config.0.client_certificate
  sensitive   = true
}

output "client_key" {
  description = "Base64 encoded client key"
  value       = azurerm_kubernetes_cluster.main.kube_config.0.client_key
  sensitive   = true
}

output "host" {
  description = "Kubernetes API server endpoint"
  value       = azurerm_kubernetes_cluster.main.kube_config.0.host
  sensitive   = true
}

output "kubelet_identity" {
  description = "Kubelet managed identity"
  value       = azurerm_kubernetes_cluster.main.kubelet_identity
}

output "oidc_issuer_url" {
  description = "OIDC issuer URL"
  value       = azurerm_kubernetes_cluster.main.oidc_issuer_url
}

output "system_node_pool_name" {
  description = "Name of the system node pool (default node pool)"
  value       = azurerm_kubernetes_cluster.main.default_node_pool[0].name
}

output "user_node_pool_id" {
  description = "ID of the user node pool"
  value       = azurerm_kubernetes_cluster_node_pool.user.id
}

output "ai_node_pool_id" {
  description = "ID of the AI/ML node pool"
  value       = var.enable_ai_node_pool ? azurerm_kubernetes_cluster_node_pool.ai[0].id : null
}

# Upgrade-related outputs
output "kubernetes_version" {
  description = "Current Kubernetes version of the cluster"
  value       = azurerm_kubernetes_cluster.main.kubernetes_version
}

output "current_kubernetes_version" {
  description = "Actual running Kubernetes version (may differ during upgrade)"
  value       = azurerm_kubernetes_cluster.main.current_kubernetes_version
}

output "node_pool_versions" {
  description = "Kubernetes versions for each node pool"
  value = {
    system = azurerm_kubernetes_cluster.main.default_node_pool[0].orchestrator_version
    user   = azurerm_kubernetes_cluster_node_pool.user.orchestrator_version
    ai     = var.enable_ai_node_pool ? azurerm_kubernetes_cluster_node_pool.ai[0].orchestrator_version : null
  }
}

output "upgrade_settings" {
  description = "Upgrade settings for each node pool"
  value = {
    system_max_surge = azurerm_kubernetes_cluster.main.default_node_pool[0].upgrade_settings[0].max_surge
    user_max_surge   = azurerm_kubernetes_cluster_node_pool.user.upgrade_settings[0].max_surge
    ai_max_surge     = var.enable_ai_node_pool ? azurerm_kubernetes_cluster_node_pool.ai[0].upgrade_settings[0].max_surge : null
  }
}
