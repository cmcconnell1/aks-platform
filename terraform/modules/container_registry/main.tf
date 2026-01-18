# Azure Container Registry
resource "azurerm_container_registry" "main" {
  name                = "${var.project_name}${var.environment}acr${random_string.suffix.result}"
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = var.sku
  admin_enabled       = var.admin_enabled

  # Public network access
  public_network_access_enabled = var.enable_public_network_access

  # Network rule set for restricting access
  dynamic "network_rule_set" {
    for_each = var.enable_public_network_access && length(var.allowed_ip_ranges) > 0 ? [1] : []
    content {
      default_action = "Deny"

      dynamic "ip_rule" {
        for_each = var.allowed_ip_ranges
        content {
          action   = "Allow"
          ip_range = ip_rule.value
        }
      }
    }
  }

  # Geo-replication for high availability
  dynamic "georeplications" {
    for_each = var.geo_replication_locations
    content {
      location                = georeplications.value.location
      zone_redundancy_enabled = georeplications.value.zone_redundancy_enabled
      tags                    = var.tags
    }
  }

  # Encryption configuration
  dynamic "encryption" {
    for_each = var.enable_encryption ? [1] : []
    content {
      enabled            = true
      key_vault_key_id   = var.encryption_key_vault_key_id
      identity_client_id = var.encryption_identity_client_id
    }
  }

  # Identity for encryption
  dynamic "identity" {
    for_each = var.enable_encryption ? [1] : []
    content {
      type         = "UserAssigned"
      identity_ids = [var.user_assigned_identity_id]
    }
  }

  # Retention policy for untagged manifests
  retention_policy {
    days    = var.retention_policy_days
    enabled = var.enable_retention_policy
  }

  # Trust policy for content trust
  trust_policy {
    enabled = var.enable_trust_policy
  }

  # Note: quarantine_policy was deprecated and removed in Azure provider v3.x
  # Vulnerability scanning is now handled through Azure Security Center/Defender

  tags = var.tags
}

# Random string for unique naming
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Private endpoint for ACR (if enabled)
resource "azurerm_private_endpoint" "acr" {
  count = var.enable_private_endpoint ? 1 : 0

  name                = "${var.project_name}-${var.environment}-acr-pe"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.private_endpoint_subnet_id

  private_service_connection {
    name                           = "${var.project_name}-${var.environment}-acr-psc"
    private_connection_resource_id = azurerm_container_registry.main.id
    subresource_names              = ["registry"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [azurerm_private_dns_zone.acr[0].id]
  }

  tags = var.tags
}

# Private DNS Zone for ACR
resource "azurerm_private_dns_zone" "acr" {
  count = var.enable_private_endpoint ? 1 : 0

  name                = "privatelink.azurecr.io"
  resource_group_name = var.resource_group_name

  tags = var.tags
}

# Link Private DNS Zone to VNet
resource "azurerm_private_dns_zone_virtual_network_link" "acr" {
  count = var.enable_private_endpoint ? 1 : 0

  name                  = "${var.project_name}-${var.environment}-acr-dns-link"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.acr[0].name
  virtual_network_id    = var.virtual_network_id

  tags = var.tags
}

# Diagnostic settings for ACR
resource "azurerm_monitor_diagnostic_setting" "acr" {
  count = var.enable_diagnostics ? 1 : 0

  name                       = "${var.project_name}-${var.environment}-acr-diagnostics"
  target_resource_id         = azurerm_container_registry.main.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category = "ContainerRegistryRepositoryEvents"
  }

  enabled_log {
    category = "ContainerRegistryLoginEvents"
  }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# Webhook for CI/CD integration (optional)
resource "azurerm_container_registry_webhook" "ci_cd" {
  count = var.enable_webhook ? 1 : 0

  name                = "${var.project_name}${var.environment}webhook"
  resource_group_name = var.resource_group_name
  registry_name       = azurerm_container_registry.main.name
  location            = var.location

  service_uri    = var.webhook_service_uri
  status         = "enabled"
  scope          = var.webhook_scope
  actions        = var.webhook_actions
  custom_headers = var.webhook_custom_headers

  tags = var.tags
}

# Task for automated image builds (optional)
resource "azurerm_container_registry_task" "build" {
  count = var.enable_build_task ? 1 : 0

  name                  = "${var.project_name}-${var.environment}-build-task"
  container_registry_id = azurerm_container_registry.main.id
  platform {
    os           = "Linux"
    architecture = "amd64"
  }

  docker_step {
    dockerfile_path      = var.build_task_dockerfile_path
    context_path         = var.build_task_context_path
    context_access_token = var.build_task_context_access_token
    image_names          = var.build_task_image_names
  }

  source_trigger {
    name           = "defaultSourceTriggerName"
    events         = ["commit"]
    repository_url = var.build_task_repository_url
    source_type    = "Github"
    branch         = var.build_task_branch

    authentication {
      token      = var.build_task_github_token
      token_type = "PAT"
    }
  }

  tags = var.tags
}
