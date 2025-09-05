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

variable "subnet_id" {
  description = "ID of the subnet for Application Gateway"
  type        = string
}

variable "key_vault_id" {
  description = "ID of the Key Vault for SSL certificates"
  type        = string
}

variable "aks_cluster_id" {
  description = "ID of the AKS cluster"
  type        = string
}

variable "subscription_id" {
  description = "Azure subscription ID"
  type        = string
}

# Application Gateway SKU Configuration
variable "sku_name" {
  description = "Name of the Application Gateway SKU"
  type        = string
  default     = "WAF_v2"
  validation {
    condition     = contains(["Standard_Small", "Standard_Medium", "Standard_Large", "Standard_v2", "WAF_Medium", "WAF_Large", "WAF_v2"], var.sku_name)
    error_message = "SKU name must be one of: Standard_Small, Standard_Medium, Standard_Large, Standard_v2, WAF_Medium, WAF_Large, WAF_v2."
  }
}

variable "sku_tier" {
  description = "Tier of the Application Gateway SKU"
  type        = string
  default     = "WAF_v2"
  validation {
    condition     = contains(["Standard", "Standard_v2", "WAF", "WAF_v2"], var.sku_tier)
    error_message = "SKU tier must be one of: Standard, Standard_v2, WAF, WAF_v2."
  }
}

variable "capacity" {
  description = "Number of Application Gateway instances"
  type        = number
  default     = 2
  validation {
    condition     = var.capacity >= 1 && var.capacity <= 125
    error_message = "Capacity must be between 1 and 125."
  }
}

# Autoscaling Configuration
variable "enable_autoscaling" {
  description = "Enable autoscaling for Application Gateway"
  type        = bool
  default     = true
}

variable "min_capacity" {
  description = "Minimum number of Application Gateway instances"
  type        = number
  default     = 1
}

variable "max_capacity" {
  description = "Maximum number of Application Gateway instances"
  type        = number
  default     = 10
}

# SSL Configuration
variable "ssl_certificate_name" {
  description = "Name of the SSL certificate"
  type        = string
  default     = null
}

variable "ssl_certificate_key_vault_secret_id" {
  description = "Key Vault secret ID for SSL certificate"
  type        = string
  default     = null
}

# WAF Configuration
variable "enable_waf" {
  description = "Enable Web Application Firewall"
  type        = bool
  default     = true
}

variable "waf_mode" {
  description = "WAF mode (Detection or Prevention)"
  type        = string
  default     = "Prevention"
  validation {
    condition     = contains(["Detection", "Prevention"], var.waf_mode)
    error_message = "WAF mode must be either Detection or Prevention."
  }
}

variable "waf_rule_set_version" {
  description = "WAF rule set version"
  type        = string
  default     = "3.2"
}

variable "waf_file_upload_limit_mb" {
  description = "WAF file upload limit in MB"
  type        = number
  default     = 100
}

variable "waf_max_request_body_size_kb" {
  description = "WAF maximum request body size in KB"
  type        = number
  default     = 128
}

variable "waf_disabled_rule_groups" {
  description = "List of WAF rule groups to disable"
  type = list(object({
    rule_group_name = string
    rules           = list(string)
  }))
  default = []
}

# AGIC Configuration
variable "enable_agic" {
  description = "Enable Application Gateway Ingress Controller"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
