output "key_vault_id" {
  description = "ID of the Key Vault"
  value       = azurerm_key_vault.main.id
}

output "key_vault_name" {
  description = "Name of the Key Vault"
  value       = azurerm_key_vault.main.name
}

output "key_vault_uri" {
  description = "URI of the Key Vault"
  value       = azurerm_key_vault.main.vault_uri
}

output "user_assigned_identity_id" {
  description = "ID of the user assigned managed identity"
  value       = azurerm_user_assigned_identity.aks.id
}

output "user_assigned_identity_client_id" {
  description = "Client ID of the user assigned managed identity"
  value       = azurerm_user_assigned_identity.aks.client_id
}

output "user_assigned_identity_principal_id" {
  description = "Principal ID of the user assigned managed identity"
  value       = azurerm_user_assigned_identity.aks.principal_id
}

output "cert_manager_identity_id" {
  description = "ID of the cert-manager user assigned managed identity"
  value       = var.enable_cert_manager ? azurerm_user_assigned_identity.cert_manager[0].id : null
}

output "cert_manager_identity_client_id" {
  description = "Client ID of the cert-manager user assigned managed identity"
  value       = var.enable_cert_manager ? azurerm_user_assigned_identity.cert_manager[0].client_id : null
}

output "cert_manager_identity_principal_id" {
  description = "Principal ID of the cert-manager user assigned managed identity"
  value       = var.enable_cert_manager ? azurerm_user_assigned_identity.cert_manager[0].principal_id : null
}

output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.id
}

output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.name
}

output "application_insights_id" {
  description = "ID of the Application Insights"
  value       = azurerm_application_insights.main.id
}

output "application_insights_name" {
  description = "Name of the Application Insights"
  value       = azurerm_application_insights.main.name
}

output "application_insights_instrumentation_key" {
  description = "Instrumentation key for Application Insights"
  value       = azurerm_application_insights.main.instrumentation_key
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "Connection string for Application Insights"
  value       = azurerm_application_insights.main.connection_string
  sensitive   = true
}

output "ssl_certificate_secret_id" {
  description = "Key Vault secret ID for SSL certificate"
  value       = var.create_demo_ssl_certificate ? azurerm_key_vault_certificate.app_gateway_ssl[0].secret_id : null
}

output "ssl_certificate_name" {
  description = "Name of the SSL certificate"
  value       = var.create_demo_ssl_certificate ? azurerm_key_vault_certificate.app_gateway_ssl[0].name : null
}

output "private_endpoint_id" {
  description = "ID of the Key Vault private endpoint"
  value       = var.enable_private_endpoint ? azurerm_private_endpoint.key_vault[0].id : null
}

output "private_dns_zone_id" {
  description = "ID of the private DNS zone"
  value       = var.enable_private_endpoint ? azurerm_private_dns_zone.key_vault[0].id : null
}

# =============================================================================
# Azure Workload Identity Outputs
# =============================================================================

output "monitoring_identity_id" {
  description = "ID of the monitoring user assigned managed identity"
  value       = var.enable_monitoring ? azurerm_user_assigned_identity.monitoring[0].id : null
}

output "monitoring_identity_client_id" {
  description = "Client ID of the monitoring user assigned managed identity"
  value       = var.enable_monitoring ? azurerm_user_assigned_identity.monitoring[0].client_id : null
}

output "monitoring_identity_principal_id" {
  description = "Principal ID of the monitoring user assigned managed identity"
  value       = var.enable_monitoring ? azurerm_user_assigned_identity.monitoring[0].principal_id : null
}

output "gitops_identity_id" {
  description = "ID of the GitOps user assigned managed identity"
  value       = var.enable_gitops ? azurerm_user_assigned_identity.gitops[0].id : null
}

output "gitops_identity_client_id" {
  description = "Client ID of the GitOps user assigned managed identity"
  value       = var.enable_gitops ? azurerm_user_assigned_identity.gitops[0].client_id : null
}

output "gitops_identity_principal_id" {
  description = "Principal ID of the GitOps user assigned managed identity"
  value       = var.enable_gitops ? azurerm_user_assigned_identity.gitops[0].principal_id : null
}

output "ai_tools_identity_id" {
  description = "ID of the AI tools user assigned managed identity"
  value       = var.enable_ai_tools ? azurerm_user_assigned_identity.ai_tools[0].id : null
}

output "ai_tools_identity_client_id" {
  description = "Client ID of the AI tools user assigned managed identity"
  value       = var.enable_ai_tools ? azurerm_user_assigned_identity.ai_tools[0].client_id : null
}

output "ai_tools_identity_principal_id" {
  description = "Principal ID of the AI tools user assigned managed identity"
  value       = var.enable_ai_tools ? azurerm_user_assigned_identity.ai_tools[0].principal_id : null
}

# Summary of all workload identity configurations
output "workload_identity_config" {
  description = "Summary of Workload Identity configuration for all components"
  value = {
    cert_manager = var.enable_cert_manager ? {
      client_id         = azurerm_user_assigned_identity.cert_manager[0].client_id
      service_account   = "system:serviceaccount:cert-manager:cert-manager"
      federated_enabled = var.enable_workload_identity && var.aks_oidc_issuer_url != null
    } : null

    monitoring = var.enable_monitoring ? {
      client_id         = azurerm_user_assigned_identity.monitoring[0].client_id
      service_accounts  = ["system:serviceaccount:monitoring:prometheus-grafana", "system:serviceaccount:monitoring:prometheus-kube-prometheus-prometheus"]
      federated_enabled = var.enable_workload_identity && var.aks_oidc_issuer_url != null
    } : null

    gitops = var.enable_gitops ? {
      client_id         = azurerm_user_assigned_identity.gitops[0].client_id
      service_accounts  = ["system:serviceaccount:argocd:argocd-server", "system:serviceaccount:argocd:argocd-application-controller"]
      federated_enabled = var.enable_workload_identity && var.aks_oidc_issuer_url != null
    } : null

    ai_tools = var.enable_ai_tools ? {
      client_id         = azurerm_user_assigned_identity.ai_tools[0].client_id
      service_accounts  = ["system:serviceaccount:ai-tools:jupyterhub-hub", "system:serviceaccount:ai-tools:mlflow"]
      federated_enabled = var.enable_workload_identity && var.aks_oidc_issuer_url != null
    } : null
  }
}
