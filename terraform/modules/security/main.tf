# User Assigned Identity for AKS
resource "azurerm_user_assigned_identity" "aks" {
  name                = "${var.project_name}-${var.environment}-aks-identity"
  resource_group_name = var.resource_group_name
  location            = var.location

  tags = var.tags
}

# User Assigned Identity for cert-manager
resource "azurerm_user_assigned_identity" "cert_manager" {
  count = var.enable_cert_manager ? 1 : 0

  name                = "${var.project_name}-${var.environment}-cert-manager-identity"
  resource_group_name = var.resource_group_name
  location            = var.location

  tags = var.tags
}

# User Assigned Identity for monitoring stack (Prometheus, Grafana)
resource "azurerm_user_assigned_identity" "monitoring" {
  count = var.enable_monitoring ? 1 : 0

  name                = "${var.project_name}-${var.environment}-monitoring-identity"
  resource_group_name = var.resource_group_name
  location            = var.location

  tags = var.tags
}

# User Assigned Identity for GitOps (ArgoCD)
resource "azurerm_user_assigned_identity" "gitops" {
  count = var.enable_gitops ? 1 : 0

  name                = "${var.project_name}-${var.environment}-gitops-identity"
  resource_group_name = var.resource_group_name
  location            = var.location

  tags = var.tags
}

# User Assigned Identity for AI Tools (JupyterHub, MLflow)
resource "azurerm_user_assigned_identity" "ai_tools" {
  count = var.enable_ai_tools ? 1 : 0

  name                = "${var.project_name}-${var.environment}-ai-tools-identity"
  resource_group_name = var.resource_group_name
  location            = var.location

  tags = var.tags
}

# =============================================================================
# Azure Workload Identity - Federated Credentials
# Note: Federated credentials are created in the root module (workload_identity.tf)
# after the AKS cluster is provisioned, as they require the OIDC issuer URL.
# This module creates only the managed identities.
# =============================================================================

# Key Vault for storing secrets and certificates
resource "azurerm_key_vault" "main" {
  name                = "${var.project_name}-${var.environment}-kv-${random_string.suffix.result}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tenant_id           = var.tenant_id
  sku_name            = var.key_vault_sku

  # Security settings
  enabled_for_disk_encryption     = true
  enabled_for_deployment          = true
  enabled_for_template_deployment = true
  purge_protection_enabled        = var.enable_purge_protection
  soft_delete_retention_days      = var.soft_delete_retention_days

  # Network access
  public_network_access_enabled = var.enable_public_network_access

  dynamic "network_acls" {
    for_each = var.enable_public_network_access ? [] : [1]
    content {
      default_action             = "Deny"
      bypass                     = "AzureServices"
      ip_rules                   = var.allowed_ip_ranges
      virtual_network_subnet_ids = var.allowed_subnet_ids
    }
  }

  tags = var.tags
}

# Random string for unique naming
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# Access policy for current user/service principal
resource "azurerm_key_vault_access_policy" "current_user" {
  key_vault_id = azurerm_key_vault.main.id
  tenant_id    = var.tenant_id
  object_id    = var.object_id

  key_permissions = [
    "Backup", "Create", "Decrypt", "Delete", "Encrypt", "Get", "Import",
    "List", "Purge", "Recover", "Restore", "Sign", "UnwrapKey", "Update",
    "Verify", "WrapKey", "Release", "Rotate", "GetRotationPolicy", "SetRotationPolicy"
  ]

  secret_permissions = [
    "Backup", "Delete", "Get", "List", "Purge", "Recover", "Restore", "Set"
  ]

  certificate_permissions = [
    "Backup", "Create", "Delete", "DeleteIssuers", "Get", "GetIssuers",
    "Import", "List", "ListIssuers", "ManageContacts", "ManageIssuers",
    "Purge", "Recover", "Restore", "SetIssuers", "Update"
  ]
}

# Access policy for AKS managed identity
resource "azurerm_key_vault_access_policy" "aks_identity" {
  key_vault_id = azurerm_key_vault.main.id
  tenant_id    = var.tenant_id
  object_id    = azurerm_user_assigned_identity.aks.principal_id

  secret_permissions = [
    "Get", "List"
  ]

  certificate_permissions = [
    "Get", "List"
  ]
}

# Access policy for cert-manager managed identity
resource "azurerm_key_vault_access_policy" "cert_manager_identity" {
  count = var.enable_cert_manager ? 1 : 0

  key_vault_id = azurerm_key_vault.main.id
  tenant_id    = var.tenant_id
  object_id    = azurerm_user_assigned_identity.cert_manager[0].principal_id

  secret_permissions = [
    "Get", "List", "Set", "Delete"
  ]

  certificate_permissions = [
    "Get", "List", "Create", "Update", "Delete", "Import"
  ]
}

# Log Analytics Workspace for monitoring
resource "azurerm_log_analytics_workspace" "main" {
  name                = "${var.project_name}-${var.environment}-law"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = var.log_analytics_sku
  retention_in_days   = var.log_retention_days

  tags = var.tags
}

# Application Insights for application monitoring
resource "azurerm_application_insights" "main" {
  name                = "${var.project_name}-${var.environment}-ai"
  location            = var.location
  resource_group_name = var.resource_group_name
  workspace_id        = azurerm_log_analytics_workspace.main.id
  application_type    = "web"

  tags = var.tags
}

# Private endpoint for Key Vault (if private access is enabled)
resource "azurerm_private_endpoint" "key_vault" {
  count = var.enable_private_endpoint ? 1 : 0

  name                = "${var.project_name}-${var.environment}-kv-pe"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.private_endpoint_subnet_id

  private_service_connection {
    name                           = "${var.project_name}-${var.environment}-kv-psc"
    private_connection_resource_id = azurerm_key_vault.main.id
    subresource_names              = ["vault"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [azurerm_private_dns_zone.key_vault[0].id]
  }

  tags = var.tags
}

# Private DNS Zone for Key Vault
resource "azurerm_private_dns_zone" "key_vault" {
  count = var.enable_private_endpoint ? 1 : 0

  name                = "privatelink.vaultcore.azure.net"
  resource_group_name = var.resource_group_name

  tags = var.tags
}

# Link Private DNS Zone to VNet
resource "azurerm_private_dns_zone_virtual_network_link" "key_vault" {
  count = var.enable_private_endpoint ? 1 : 0

  name                  = "${var.project_name}-${var.environment}-kv-dns-link"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.key_vault[0].name
  virtual_network_id    = var.virtual_network_id

  tags = var.tags
}

# Example SSL certificate for Application Gateway (self-signed for demo)
resource "azurerm_key_vault_certificate" "app_gateway_ssl" {
  count = var.create_demo_ssl_certificate ? 1 : 0

  name         = "app-gateway-ssl"
  key_vault_id = azurerm_key_vault.main.id

  certificate_policy {
    issuer_parameters {
      name = "Self"
    }

    key_properties {
      exportable = true
      key_size   = 2048
      key_type   = "RSA"
      reuse_key  = true
    }

    lifetime_action {
      action {
        action_type = "AutoRenew"
      }

      trigger {
        days_before_expiry = 30
      }
    }

    secret_properties {
      content_type = "application/x-pkcs12"
    }

    x509_certificate_properties {
      extended_key_usage = ["1.3.6.1.5.5.7.3.1"]

      key_usage = [
        "cRLSign",
        "dataEncipherment",
        "digitalSignature",
        "keyAgreement",
        "keyCertSign",
        "keyEncipherment",
      ]

      subject_alternative_names {
        dns_names = var.ssl_certificate_dns_names
      }

      subject            = "CN=${var.ssl_certificate_subject}"
      validity_in_months = 12
    }
  }

  depends_on = [azurerm_key_vault_access_policy.current_user]
}
