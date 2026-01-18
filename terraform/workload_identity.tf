# =============================================================================
# Azure Workload Identity Configuration
# =============================================================================
# This file creates federated identity credentials that establish trust between
# Kubernetes ServiceAccounts and Azure AD Managed Identities.
#
# Azure Workload Identity is the 2026 best practice for pod authentication,
# replacing the deprecated AAD Pod Identity.
#
# How it works:
# 1. AKS cluster has OIDC issuer enabled (workload_identity_enabled = true)
# 2. Managed identities are created for each component (in security module)
# 3. Federated credentials link Kubernetes ServiceAccounts to managed identities
# 4. Pods with matching ServiceAccount labels can authenticate to Azure services
# =============================================================================

# -----------------------------------------------------------------------------
# cert-manager Federated Credential
# Allows cert-manager to authenticate with Azure DNS for DNS01 challenges
# -----------------------------------------------------------------------------
resource "azurerm_federated_identity_credential" "cert_manager" {
  count = var.enable_cert_manager ? 1 : 0

  name                = "${var.project_name}-${var.environment}-cert-manager"
  resource_group_name = azurerm_resource_group.main.name
  parent_id           = module.security.cert_manager_identity_id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = module.aks.oidc_issuer_url
  subject             = "system:serviceaccount:cert-manager:cert-manager"

  depends_on = [module.aks, module.security]
}

# -----------------------------------------------------------------------------
# Monitoring Federated Credentials
# Allows Prometheus and Grafana to authenticate with Azure services
# -----------------------------------------------------------------------------
resource "azurerm_federated_identity_credential" "grafana" {
  count = var.enable_monitoring ? 1 : 0

  name                = "${var.project_name}-${var.environment}-grafana"
  resource_group_name = azurerm_resource_group.main.name
  parent_id           = module.security.monitoring_identity_id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = module.aks.oidc_issuer_url
  subject             = "system:serviceaccount:monitoring:prometheus-grafana"

  depends_on = [module.aks, module.security]
}

resource "azurerm_federated_identity_credential" "prometheus" {
  count = var.enable_monitoring ? 1 : 0

  name                = "${var.project_name}-${var.environment}-prometheus"
  resource_group_name = azurerm_resource_group.main.name
  parent_id           = module.security.monitoring_identity_id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = module.aks.oidc_issuer_url
  subject             = "system:serviceaccount:monitoring:prometheus-kube-prometheus-prometheus"

  depends_on = [module.aks, module.security]
}

# -----------------------------------------------------------------------------
# GitOps (ArgoCD) Federated Credentials
# Allows ArgoCD to authenticate with Azure services for repository access
# -----------------------------------------------------------------------------
resource "azurerm_federated_identity_credential" "argocd_server" {
  count = var.enable_argocd ? 1 : 0

  name                = "${var.project_name}-${var.environment}-argocd-server"
  resource_group_name = azurerm_resource_group.main.name
  parent_id           = module.security.gitops_identity_id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = module.aks.oidc_issuer_url
  subject             = "system:serviceaccount:argocd:argocd-server"

  depends_on = [module.aks, module.security]
}

resource "azurerm_federated_identity_credential" "argocd_application_controller" {
  count = var.enable_argocd ? 1 : 0

  name                = "${var.project_name}-${var.environment}-argocd-app-controller"
  resource_group_name = azurerm_resource_group.main.name
  parent_id           = module.security.gitops_identity_id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = module.aks.oidc_issuer_url
  subject             = "system:serviceaccount:argocd:argocd-application-controller"

  depends_on = [module.aks, module.security]
}

resource "azurerm_federated_identity_credential" "argocd_repo_server" {
  count = var.enable_argocd ? 1 : 0

  name                = "${var.project_name}-${var.environment}-argocd-repo-server"
  resource_group_name = azurerm_resource_group.main.name
  parent_id           = module.security.gitops_identity_id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = module.aks.oidc_issuer_url
  subject             = "system:serviceaccount:argocd:argocd-repo-server"

  depends_on = [module.aks, module.security]
}

# -----------------------------------------------------------------------------
# AI Tools Federated Credentials
# Allows JupyterHub and MLflow to authenticate with Azure services
# -----------------------------------------------------------------------------
resource "azurerm_federated_identity_credential" "jupyterhub" {
  count = var.enable_ai_tools && var.enable_jupyter_hub ? 1 : 0

  name                = "${var.project_name}-${var.environment}-jupyterhub"
  resource_group_name = azurerm_resource_group.main.name
  parent_id           = module.security.ai_tools_identity_id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = module.aks.oidc_issuer_url
  subject             = "system:serviceaccount:ai-tools:hub"

  depends_on = [module.aks, module.security]
}

resource "azurerm_federated_identity_credential" "mlflow" {
  count = var.enable_ai_tools && var.enable_mlflow ? 1 : 0

  name                = "${var.project_name}-${var.environment}-mlflow"
  resource_group_name = azurerm_resource_group.main.name
  parent_id           = module.security.ai_tools_identity_id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = module.aks.oidc_issuer_url
  subject             = "system:serviceaccount:ai-tools:mlflow"

  depends_on = [module.aks, module.security]
}

# -----------------------------------------------------------------------------
# Application Gateway for Containers (AGC) - ALB Controller
# The federated credential for ALB Controller is managed within the AGC module
# (terraform/modules/agc/main.tf) as it needs to be created before the Helm
# release and tied to the specific ALB Controller ServiceAccount.
#
# ServiceAccount: azure-alb-system:alb-controller-sa
# Role: Manages AGC frontend and routing configuration
# -----------------------------------------------------------------------------
# NOTE: AGC workload identity is configured in module.agc
