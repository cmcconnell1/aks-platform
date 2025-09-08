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

# ACR Configuration
variable "sku" {
  description = "SKU for Azure Container Registry"
  type        = string
  default     = "Premium"
  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.sku)
    error_message = "SKU must be one of: Basic, Standard, Premium."
  }
}

variable "admin_enabled" {
  description = "Enable admin user for ACR"
  type        = bool
  default     = false
}

variable "enable_public_network_access" {
  description = "Enable public network access to ACR"
  type        = bool
  default     = false
}

variable "allowed_ip_ranges" {
  description = "List of allowed IP ranges for ACR access"
  type        = list(string)
  default     = []
}

# Geo-replication
variable "geo_replication_locations" {
  description = "List of geo-replication locations"
  type = list(object({
    location                = string
    zone_redundancy_enabled = bool
  }))
  default = []
}

# Encryption
variable "enable_encryption" {
  description = "Enable customer-managed key encryption"
  type        = bool
  default     = false
}

variable "encryption_key_vault_key_id" {
  description = "Key Vault key ID for encryption"
  type        = string
  default     = null
}

variable "encryption_identity_client_id" {
  description = "Client ID of the identity for encryption"
  type        = string
  default     = null
}

variable "user_assigned_identity_id" {
  description = "ID of the user assigned identity"
  type        = string
  default     = null
}

# Policies
variable "enable_retention_policy" {
  description = "Enable retention policy for untagged manifests"
  type        = bool
  default     = true
}

variable "retention_policy_days" {
  description = "Number of days to retain untagged manifests"
  type        = number
  default     = 7
}

variable "enable_trust_policy" {
  description = "Enable content trust policy"
  type        = bool
  default     = false
}

# Note: enable_quarantine_policy variable removed as quarantine_policy
# was deprecated and removed in Azure provider v3.x

# Private Endpoint
variable "enable_private_endpoint" {
  description = "Enable private endpoint for ACR"
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

# Monitoring
variable "enable_diagnostics" {
  description = "Enable diagnostic settings"
  type        = bool
  default     = true
}

variable "log_analytics_workspace_id" {
  description = "Log Analytics workspace ID for diagnostics"
  type        = string
  default     = null
}

# Webhook Configuration
variable "enable_webhook" {
  description = "Enable webhook for CI/CD integration"
  type        = bool
  default     = false
}

variable "webhook_service_uri" {
  description = "Service URI for webhook"
  type        = string
  default     = null
}

variable "webhook_scope" {
  description = "Scope for webhook"
  type        = string
  default     = ""
}

variable "webhook_actions" {
  description = "Actions that trigger webhook"
  type        = list(string)
  default     = ["push"]
}

variable "webhook_custom_headers" {
  description = "Custom headers for webhook"
  type        = map(string)
  default     = {}
}

# Build Task Configuration
variable "enable_build_task" {
  description = "Enable automated build task"
  type        = bool
  default     = false
}

variable "build_task_dockerfile_path" {
  description = "Path to Dockerfile for build task"
  type        = string
  default     = "Dockerfile"
}

variable "build_task_context_path" {
  description = "Context path for build task"
  type        = string
  default     = "."
}

variable "build_task_context_access_token" {
  description = "Access token for build context"
  type        = string
  default     = null
  sensitive   = true
}

variable "build_task_image_names" {
  description = "Image names for build task"
  type        = list(string)
  default     = []
}

variable "build_task_repository_url" {
  description = "Repository URL for build task"
  type        = string
  default     = null
}

variable "build_task_branch" {
  description = "Branch for build task"
  type        = string
  default     = "main"
}

variable "build_task_github_token" {
  description = "GitHub token for build task"
  type        = string
  default     = null
  sensitive   = true
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
