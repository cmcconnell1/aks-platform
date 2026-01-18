variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
}

variable "cluster_name" {
  description = "Name of the AKS cluster"
  type        = string
}

variable "argocd_namespace" {
  description = "Namespace for ArgoCD"
  type        = string
  default     = "argocd"
}

variable "argocd_domain" {
  description = "Domain for ArgoCD server"
  type        = string
  default     = "argocd.local"
}

variable "enable_insecure_mode" {
  description = "Enable insecure mode for ArgoCD server"
  type        = bool
  default     = true
}

variable "server_replicas" {
  description = "Number of ArgoCD server replicas"
  type        = number
  default     = 2
}

variable "controller_replicas" {
  description = "Number of ArgoCD controller replicas"
  type        = number
  default     = 1
}

variable "repo_server_replicas" {
  description = "Number of ArgoCD repo server replicas"
  type        = number
  default     = 2
}

variable "enable_application_set" {
  description = "Enable ApplicationSet controller"
  type        = bool
  default     = true
}

variable "enable_notifications" {
  description = "Enable ArgoCD notifications"
  type        = bool
  default     = false
}

variable "service_type" {
  description = "Service type for ArgoCD server"
  type        = string
  default     = "ClusterIP"
}

variable "service_annotations" {
  description = "Annotations for ArgoCD server service"
  type        = map(string)
  default     = {}
}

variable "enable_ingress" {
  description = "Enable ingress for ArgoCD server"
  type        = bool
  default     = true
}

variable "ingress_annotations" {
  description = "Annotations for ArgoCD ingress"
  type        = map(string)
  default = {
    "kubernetes.io/ingress.class"                  = "azure/application-gateway"
    "appgw.ingress.kubernetes.io/ssl-redirect"     = "true"
    "appgw.ingress.kubernetes.io/backend-protocol" = "http"
  }
}

variable "ingress_hosts" {
  description = "Hosts for ArgoCD ingress"
  type        = list(string)
  default     = []
}

variable "ingress_tls" {
  description = "TLS configuration for ArgoCD ingress"
  type = list(object({
    secretName = string
    hosts      = list(string)
  }))
  default = []
}

variable "rbac_policy" {
  description = "RBAC policy for ArgoCD"
  type        = string
  default     = ""
}

# OIDC Configuration
variable "enable_oidc" {
  description = "Enable OIDC authentication"
  type        = bool
  default     = false
}

variable "tenant_id" {
  description = "Azure AD tenant ID for OIDC"
  type        = string
  default     = null
}

variable "oidc_client_id" {
  description = "OIDC client ID"
  type        = string
  default     = null
}

variable "oidc_client_secret" {
  description = "OIDC client secret"
  type        = string
  default     = null
  sensitive   = true
}

# Git Repository Configuration
variable "git_repositories" {
  description = "Git repositories configuration"
  type        = any
  default     = null
}

# App of Apps Configuration
variable "enable_app_of_apps" {
  description = "Enable app-of-apps pattern"
  type        = bool
  default     = false
}

variable "app_of_apps_repo_url" {
  description = "Repository URL for app-of-apps"
  type        = string
  default     = null
}

variable "app_of_apps_target_revision" {
  description = "Target revision for app-of-apps"
  type        = string
  default     = "HEAD"
}

variable "app_of_apps_path" {
  description = "Path in repository for app-of-apps"
  type        = string
  default     = "apps"
}

variable "create_cli_config" {
  description = "Create ArgoCD CLI configuration secret"
  type        = bool
  default     = false
}
