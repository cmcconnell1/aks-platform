# Public IP for Application Gateway
resource "azurerm_public_ip" "app_gateway" {
  name                = "${var.project_name}-${var.environment}-appgw-pip"
  resource_group_name = var.resource_group_name
  location            = var.location
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = ["1", "2", "3"]

  tags = var.tags
}

# User Assigned Identity for Application Gateway
resource "azurerm_user_assigned_identity" "app_gateway" {
  name                = "${var.project_name}-${var.environment}-appgw-identity"
  resource_group_name = var.resource_group_name
  location            = var.location

  tags = var.tags
}

# Role assignment for Key Vault access
resource "azurerm_role_assignment" "app_gateway_keyvault" {
  scope                = var.key_vault_id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.app_gateway.principal_id
}

# Application Gateway
resource "azurerm_application_gateway" "main" {
  name                = "${var.project_name}-${var.environment}-appgw"
  resource_group_name = var.resource_group_name
  location            = var.location
  enable_http2        = true
  zones               = ["1", "2", "3"]

  # SKU Configuration
  sku {
    name     = var.sku_name
    tier     = var.sku_tier
    capacity = var.capacity
  }

  # Autoscale Configuration
  dynamic "autoscale_configuration" {
    for_each = var.enable_autoscaling ? [1] : []
    content {
      min_capacity = var.min_capacity
      max_capacity = var.max_capacity
    }
  }

  # Gateway IP Configuration
  gateway_ip_configuration {
    name      = "appGatewayIpConfig"
    subnet_id = var.subnet_id
  }

  # Frontend Port Configuration
  frontend_port {
    name = "port_80"
    port = 80
  }

  frontend_port {
    name = "port_443"
    port = 443
  }

  # Frontend IP Configuration
  frontend_ip_configuration {
    name                 = "appGwPublicFrontendIp"
    public_ip_address_id = azurerm_public_ip.app_gateway.id
  }

  # Backend Address Pool (will be managed by AGIC)
  backend_address_pool {
    name = "defaultaddresspool"
  }

  # Backend HTTP Settings (will be managed by AGIC)
  backend_http_settings {
    name                  = "defaulthttpsetting"
    cookie_based_affinity = "Disabled"
    port                  = 80
    protocol              = "Http"
    request_timeout       = 60
  }

  # HTTP Listener
  http_listener {
    name                           = "httpListener"
    frontend_ip_configuration_name = "appGwPublicFrontendIp"
    frontend_port_name             = "port_80"
    protocol                       = "Http"
  }

  # HTTPS Listener (if SSL certificate is provided)
  dynamic "http_listener" {
    for_each = var.ssl_certificate_name != null ? [1] : []
    content {
      name                           = "httpsListener"
      frontend_ip_configuration_name = "appGwPublicFrontendIp"
      frontend_port_name             = "port_443"
      protocol                       = "Https"
      ssl_certificate_name           = var.ssl_certificate_name
    }
  }

  # SSL Certificate from Key Vault
  dynamic "ssl_certificate" {
    for_each = var.ssl_certificate_name != null ? [1] : []
    content {
      name                = var.ssl_certificate_name
      key_vault_secret_id = var.ssl_certificate_key_vault_secret_id
    }
  }

  # Request Routing Rule for HTTP
  request_routing_rule {
    name                       = "httpRoutingRule"
    rule_type                  = "Basic"
    http_listener_name         = "httpListener"
    backend_address_pool_name  = "defaultaddresspool"
    backend_http_settings_name = "defaulthttpsetting"
    priority                   = 100
  }

  # Request Routing Rule for HTTPS
  dynamic "request_routing_rule" {
    for_each = var.ssl_certificate_name != null ? [1] : []
    content {
      name                       = "httpsRoutingRule"
      rule_type                  = "Basic"
      http_listener_name         = "httpsListener"
      backend_address_pool_name  = "defaultaddresspool"
      backend_http_settings_name = "defaulthttpsetting"
      priority                   = 200
    }
  }

  # Identity for Key Vault access
  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.app_gateway.id]
  }

  # WAF Configuration
  dynamic "waf_configuration" {
    for_each = var.enable_waf ? [1] : []
    content {
      enabled                  = true
      firewall_mode            = var.waf_mode
      rule_set_type            = "OWASP"
      rule_set_version         = var.waf_rule_set_version
      file_upload_limit_mb     = var.waf_file_upload_limit_mb
      request_body_check       = true
      max_request_body_size_kb = var.waf_max_request_body_size_kb

      dynamic "disabled_rule_group" {
        for_each = var.waf_disabled_rule_groups
        content {
          rule_group_name = disabled_rule_group.value.rule_group_name
          rules           = disabled_rule_group.value.rules
        }
      }
    }
  }

  # Probe for health checks (will be managed by AGIC)
  probe {
    name                                      = "defaultprobe"
    protocol                                  = "Http"
    path                                      = "/"
    host                                      = "localhost"
    interval                                  = 30
    timeout                                   = 30
    unhealthy_threshold                       = 3
    pick_host_name_from_backend_http_settings = false
    minimum_servers                           = 0

    match {
      status_code = ["200-399"]
    }
  }

  tags = var.tags

  depends_on = [
    azurerm_role_assignment.app_gateway_keyvault
  ]
}

# AGIC Add-on for AKS (requires AKS cluster to be created first)
resource "azurerm_kubernetes_cluster_extension" "agic" {
  count = var.enable_agic ? 1 : 0

  name           = "agic"
  cluster_id     = var.aks_cluster_id
  extension_type = "Microsoft.AzureML.Kubernetes"

  configuration_settings = {
    "appgw.subscriptionId"       = var.subscription_id
    "appgw.resourceGroup"        = var.resource_group_name
    "appgw.name"                 = azurerm_application_gateway.main.name
    "appgw.usePrivateIP"         = "false"
    "armAuth.type"               = "workloadIdentity"
    "armAuth.identityResourceID" = azurerm_user_assigned_identity.app_gateway.id
    "armAuth.identityClientID"   = azurerm_user_assigned_identity.app_gateway.client_id
  }
}

# Role assignment for AGIC to manage Application Gateway
resource "azurerm_role_assignment" "agic_app_gateway_contributor" {
  scope                = azurerm_application_gateway.main.id
  role_definition_name = "Contributor"
  principal_id         = azurerm_user_assigned_identity.app_gateway.principal_id
}

# Role assignment for AGIC to read resource groups
resource "azurerm_role_assignment" "agic_resource_group_reader" {
  scope                = "/subscriptions/${var.subscription_id}/resourceGroups/${var.resource_group_name}"
  role_definition_name = "Reader"
  principal_id         = azurerm_user_assigned_identity.app_gateway.principal_id
}
