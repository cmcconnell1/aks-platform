# Local values for resource naming and configuration
locals {
  resource_group_name = var.resource_group_name != null ? var.resource_group_name : "${var.project_name}-${var.environment}-rg"
  cluster_name        = "${var.project_name}-${var.environment}-aks"
  
  # Merge environment-specific tags with provided tags
  common_tags = merge(var.tags, {
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "Terraform"
  })
}

# Resource Group
resource "azurerm_resource_group" "main" {
  name     = local.resource_group_name
  location = var.location
  tags     = local.common_tags
}

# Networking Module
module "networking" {
  source = "./modules/networking"
  
  resource_group_name                    = azurerm_resource_group.main.name
  location                              = azurerm_resource_group.main.location
  environment                           = var.environment
  project_name                          = var.project_name
  vnet_address_space                    = var.vnet_address_space
  aks_subnet_address_prefix             = var.aks_subnet_address_prefix
  app_gateway_subnet_address_prefix     = var.app_gateway_subnet_address_prefix
  private_endpoint_subnet_address_prefix = var.private_endpoint_subnet_address_prefix
  tags                                  = local.common_tags
}

# Security Module (Key Vault, Managed Identity)
module "security" {
  source = "./modules/security"

  resource_group_name           = azurerm_resource_group.main.name
  location                     = azurerm_resource_group.main.location
  environment                  = var.environment
  project_name                 = var.project_name
  tenant_id                    = data.azurerm_client_config.current.tenant_id
  object_id                    = data.azurerm_client_config.current.object_id

  # Private endpoint configuration
  enable_private_endpoint      = var.enable_private_endpoints
  private_endpoint_subnet_id   = module.networking.private_endpoints_subnet_id
  virtual_network_id           = module.networking.vnet_id

  # SSL certificate configuration
  create_demo_ssl_certificate  = var.create_demo_ssl_certificate
  ssl_certificate_subject      = var.ssl_certificate_subject
  ssl_certificate_dns_names    = var.ssl_certificate_dns_names

  # cert-manager configuration
  enable_cert_manager          = var.enable_cert_manager

  tags = local.common_tags

  depends_on = [module.networking]
}

# Container Registry
module "container_registry" {
  source = "./modules/container_registry"

  resource_group_name            = azurerm_resource_group.main.name
  location                      = azurerm_resource_group.main.location
  environment                   = var.environment
  project_name                  = var.project_name

  # Private endpoint configuration
  enable_private_endpoint       = var.enable_private_endpoints
  private_endpoint_subnet_id    = module.networking.private_endpoints_subnet_id
  virtual_network_id            = module.networking.vnet_id

  # Monitoring
  log_analytics_workspace_id    = module.security.log_analytics_workspace_id

  tags = local.common_tags

  depends_on = [module.networking, module.security]
}

# AKS Cluster
module "aks" {
  source = "./modules/aks"
  
  resource_group_name     = azurerm_resource_group.main.name
  location               = azurerm_resource_group.main.location
  cluster_name           = local.cluster_name
  environment            = var.environment
  project_name           = var.project_name
  kubernetes_version     = var.kubernetes_version
  
  # Networking
  vnet_subnet_id         = module.networking.aks_subnet_id
  enable_private_cluster = var.enable_private_cluster
  authorized_ip_ranges   = var.authorized_ip_ranges
  
  # Node pools
  node_count             = var.aks_node_count
  node_vm_size          = var.aks_node_vm_size
  max_node_count        = var.aks_max_node_count
  min_node_count        = var.aks_min_node_count
  enable_spot_instances = var.enable_spot_instances
  
  # AI/ML node pool
  enable_ai_node_pool   = var.enable_ai_node_pool
  ai_node_vm_size      = var.ai_node_vm_size
  ai_node_count        = var.ai_node_count
  
  # Security
  key_vault_id                         = module.security.key_vault_id
  user_assigned_identity_id            = module.security.user_assigned_identity_id
  user_assigned_identity_principal_id  = module.security.user_assigned_identity_principal_id

  # Container Registry
  container_registry_id = module.container_registry.registry_id

  # Monitoring
  log_analytics_workspace_id = module.security.log_analytics_workspace_id
  
  tags = local.common_tags
  
  depends_on = [
    module.networking,
    module.security,
    module.container_registry
  ]
}

# Application Gateway with AGIC
module "application_gateway" {
  source = "./modules/application_gateway"
  count  = var.enable_application_gateway ? 1 : 0

  resource_group_name = azurerm_resource_group.main.name
  location           = azurerm_resource_group.main.location
  environment        = var.environment
  project_name       = var.project_name

  # Networking
  subnet_id          = module.networking.app_gateway_subnet_id

  # Security
  key_vault_id       = module.security.key_vault_id

  # AKS integration
  aks_cluster_id     = module.aks.cluster_id
  subscription_id    = data.azurerm_client_config.current.subscription_id

  # SSL certificate (if demo certificate is created)
  ssl_certificate_name                = var.create_demo_ssl_certificate ? module.security.ssl_certificate_name : null
  ssl_certificate_key_vault_secret_id = var.create_demo_ssl_certificate ? module.security.ssl_certificate_secret_id : null

  tags = local.common_tags

  depends_on = [module.aks, module.security]
}

# cert-manager Module for Let's Encrypt
module "cert_manager" {
  source = "./modules/cert_manager"
  count  = var.enable_cert_manager ? 1 : 0

  cert_manager_identity_client_id = module.security.cert_manager_identity_client_id
  letsencrypt_email              = var.letsencrypt_email
  enable_letsencrypt_staging     = var.enable_letsencrypt_staging
  enable_letsencrypt_prod        = var.enable_letsencrypt_prod

  # DNS01 solver configuration (for wildcard certificates)
  enable_dns01_solver     = false  # Set to true if you have Azure DNS
  subscription_id         = data.azurerm_client_config.current.subscription_id
  tenant_id              = data.azurerm_client_config.current.tenant_id

  depends_on = [module.aks, module.security]
}

# Monitoring Module
module "monitoring" {
  source = "./modules/monitoring"
  count  = var.enable_monitoring ? 1 : 0

  # Grafana ingress configuration
  enable_grafana_ingress = var.enable_application_gateway
  grafana_ingress_hosts  = ["grafana.${var.ssl_certificate_subject}"]

  depends_on = [module.aks, module.application_gateway]
}

# GitOps Module (ArgoCD)
module "gitops" {
  source = "./modules/gitops"
  count  = var.enable_argocd ? 1 : 0

  environment      = var.environment
  cluster_name     = local.cluster_name
  argocd_namespace = var.argocd_namespace
  argocd_domain    = "argocd.${var.ssl_certificate_subject}"
  enable_ingress   = var.enable_application_gateway

  depends_on = [module.aks, module.application_gateway]
}

# AI Tools Module
module "ai_tools" {
  source = "./modules/ai_tools"
  count  = var.enable_ai_tools ? 1 : 0

  enable_jupyter_hub = var.enable_jupyter_hub
  enable_mlflow      = var.enable_mlflow
  enable_kubeflow    = var.enable_kubeflow
  enable_gpu_support = var.enable_ai_node_pool

  # Ingress configuration
  jupyter_ingress_hosts = ["jupyter.${var.ssl_certificate_subject}"]
  mlflow_ingress_hosts  = ["mlflow.${var.ssl_certificate_subject}"]

  depends_on = [module.aks, module.application_gateway]
}
