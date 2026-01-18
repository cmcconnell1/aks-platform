# Application Gateway for Containers (AGC) Module
# This module deploys AGC with ALB Controller for cloud-native container load balancing

# User Assigned Identity for ALB Controller
resource "azurerm_user_assigned_identity" "alb_controller" {
  name                = "${var.project_name}-${var.environment}-alb-controller-identity"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
}

# Application Gateway for Containers
resource "azurerm_application_gateway_for_containers" "main" {
  name                = "${var.project_name}-${var.environment}-agc"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
}

# AGC Frontend for external traffic
resource "azurerm_application_gateway_for_containers_frontend" "main" {
  name                                          = "${var.project_name}-${var.environment}-agc-frontend"
  application_gateway_for_containers_id         = azurerm_application_gateway_for_containers.main.id
  tags                                          = var.tags
}

# AGC Association - Links AGC to the subnet
resource "azurerm_application_gateway_for_containers_association" "main" {
  name                                          = "${var.project_name}-${var.environment}-agc-association"
  application_gateway_for_containers_id         = azurerm_application_gateway_for_containers.main.id
  subnet_id                                     = var.subnet_id
}

# Role assignments for ALB Controller

# Reader role on the resource group
resource "azurerm_role_assignment" "alb_controller_rg_reader" {
  scope                = "/subscriptions/${var.subscription_id}/resourceGroups/${var.resource_group_name}"
  role_definition_name = "Reader"
  principal_id         = azurerm_user_assigned_identity.alb_controller.principal_id
}

# AppGw for Containers Configuration Manager role on AGC
resource "azurerm_role_assignment" "alb_controller_agc_config_manager" {
  scope                = azurerm_application_gateway_for_containers.main.id
  role_definition_name = "AppGw for Containers Configuration Manager"
  principal_id         = azurerm_user_assigned_identity.alb_controller.principal_id
}

# Network Contributor role on the AGC subnet for association management
resource "azurerm_role_assignment" "alb_controller_subnet_contributor" {
  scope                = var.subnet_id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.alb_controller.principal_id
}

# Federated Identity Credential for ALB Controller workload identity
resource "azurerm_federated_identity_credential" "alb_controller" {
  name                = "${var.project_name}-${var.environment}-alb-controller"
  resource_group_name = var.resource_group_name
  parent_id           = azurerm_user_assigned_identity.alb_controller.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = var.aks_oidc_issuer_url
  subject             = "system:serviceaccount:azure-alb-system:alb-controller-sa"
}

# ALB Controller Helm Release
resource "helm_release" "alb_controller" {
  name             = "alb-controller"
  repository       = "oci://mcr.microsoft.com/application-lb/charts"
  chart            = "alb-controller"
  version          = var.alb_controller_version
  namespace        = "azure-alb-system"
  create_namespace = true

  values = [
    yamlencode({
      albController = {
        namespace = "azure-alb-system"
        podIdentity = {
          clientID = azurerm_user_assigned_identity.alb_controller.client_id
        }
      }
    })
  ]

  set {
    name  = "albController.podIdentity.clientID"
    value = azurerm_user_assigned_identity.alb_controller.client_id
  }

  depends_on = [
    azurerm_federated_identity_credential.alb_controller,
    azurerm_role_assignment.alb_controller_rg_reader,
    azurerm_role_assignment.alb_controller_agc_config_manager,
    azurerm_role_assignment.alb_controller_subnet_contributor
  ]
}

# Gateway API CRDs (required for AGC)
resource "helm_release" "gateway_api_crds" {
  name       = "gateway-api"
  repository = "https://kubernetes-sigs.github.io/gateway-api"
  chart      = "gateway-api"
  version    = var.gateway_api_version
  namespace  = "gateway-system"
  create_namespace = true

  set {
    name  = "installCRDs"
    value = "true"
  }
}

# Kubernetes Gateway resource for AGC
resource "kubernetes_manifest" "gateway" {
  count = var.create_default_gateway ? 1 : 0

  manifest = {
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "Gateway"
    metadata = {
      name      = "${var.project_name}-${var.environment}-gateway"
      namespace = var.gateway_namespace
      annotations = {
        "alb.networking.azure.io/alb-id" = azurerm_application_gateway_for_containers.main.id
      }
    }
    spec = {
      gatewayClassName = "azure-alb-external"
      listeners = [
        {
          name     = "http"
          port     = 80
          protocol = "HTTP"
          allowedRoutes = {
            namespaces = {
              from = "All"
            }
          }
        },
        {
          name     = "https"
          port     = 443
          protocol = "HTTPS"
          tls = var.enable_https ? {
            mode = "Terminate"
            certificateRefs = var.tls_certificate_refs
          } : null
          allowedRoutes = {
            namespaces = {
              from = "All"
            }
          }
        }
      ]
      addresses = [
        {
          type  = "alb.networking.azure.io/alb-frontend"
          value = azurerm_application_gateway_for_containers_frontend.main.id
        }
      ]
    }
  }

  depends_on = [
    helm_release.alb_controller,
    helm_release.gateway_api_crds,
    azurerm_application_gateway_for_containers_frontend.main,
    azurerm_application_gateway_for_containers_association.main
  ]
}
