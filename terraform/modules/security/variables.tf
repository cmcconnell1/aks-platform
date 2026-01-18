variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "tenant_id" {
  description = "Azure AD tenant ID"
  type        = string
}

variable "object_id" {
  description = "Object ID of the current user/service principal"
  type        = string
}

# Key Vault Configuration
variable "key_vault_sku" {
  description = "SKU for Key Vault"
  type        = string
  default     = "standard"
  validation {
    condition     = contains(["standard", "premium"], var.key_vault_sku)
    error_message = "Key Vault SKU must be either 'standard' or 'premium'."
  }
}

variable "enable_purge_protection" {
  description = "Enable purge protection for Key Vault"
  type        = bool
  default     = true
}

variable "soft_delete_retention_days" {
  description = "Number of days to retain soft-deleted Key Vault"
  type        = number
  default     = 90
  validation {
    condition     = var.soft_delete_retention_days >= 7 && var.soft_delete_retention_days <= 90
    error_message = "Soft delete retention days must be between 7 and 90."
  }
}

variable "enable_public_network_access" {
  description = "Enable public network access to Key Vault"
  type        = bool
  default     = false
}

variable "allowed_ip_ranges" {
  description = "List of allowed IP ranges for Key Vault access"
  type        = list(string)
  default     = []
}

variable "allowed_subnet_ids" {
  description = "List of allowed subnet IDs for Key Vault access"
  type        = list(string)
  default     = []
}

# Private Endpoint Configuration
variable "enable_private_endpoint" {
  description = "Enable private endpoint for Key Vault"
  type        = bool
  default     = true
}

variable "private_endpoint_subnet_id" {
  description = "Subnet ID for private endpoint"
  type        = string
  default     = null
}

variable "virtual_network_id" {
  description = "Virtual network ID for private DNS zone link"
  type        = string
  default     = null
}

# Log Analytics Configuration
variable "log_analytics_sku" {
  description = "SKU for Log Analytics workspace"
  type        = string
  default     = "PerGB2018"
}

variable "log_retention_days" {
  description = "Number of days to retain logs"
  type        = number
  default     = 30
  validation {
    condition     = var.log_retention_days >= 30 && var.log_retention_days <= 730
    error_message = "Log retention days must be between 30 and 730."
  }
}

# SSL Certificate Configuration
variable "create_demo_ssl_certificate" {
  description = "Create a demo SSL certificate for testing"
  type        = bool
  default     = false
}

variable "ssl_certificate_subject" {
  description = "Subject for SSL certificate"
  type        = string
  default     = "example.com"
}

variable "ssl_certificate_dns_names" {
  description = "DNS names for SSL certificate"
  type        = list(string)
  default     = ["example.com", "*.example.com"]
}

variable "enable_cert_manager" {
  description = "Enable cert-manager managed identity creation"
  type        = bool
  default     = false
}

# =============================================================================
# Azure Workload Identity Configuration
# =============================================================================

variable "aks_oidc_issuer_url" {
  description = "OIDC issuer URL from AKS cluster for federated identity credentials"
  type        = string
  default     = null
}

variable "enable_workload_identity" {
  description = "Enable Azure Workload Identity for pod authentication"
  type        = bool
  default     = true
}

variable "enable_monitoring" {
  description = "Enable monitoring stack (creates managed identity)"
  type        = bool
  default     = true
}

variable "enable_gitops" {
  description = "Enable GitOps/ArgoCD (creates managed identity)"
  type        = bool
  default     = true
}

variable "enable_ai_tools" {
  description = "Enable AI tools (creates managed identity)"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
