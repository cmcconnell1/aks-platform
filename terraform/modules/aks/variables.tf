variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "cluster_name" {
  description = "Name of the AKS cluster"
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

variable "kubernetes_version" {
  description = "Kubernetes version for AKS cluster"
  type        = string
  default     = null
}

# Networking variables
variable "vnet_subnet_id" {
  description = "ID of the subnet for AKS nodes"
  type        = string
}

variable "enable_private_cluster" {
  description = "Enable private AKS cluster"
  type        = bool
  default     = true
}

variable "authorized_ip_ranges" {
  description = "Authorized IP ranges for AKS API server access"
  type        = list(string)
  default     = []
}

# Node pool variables
variable "node_count" {
  description = "Initial number of nodes in the default node pool"
  type        = number
  default     = 2
}

variable "node_vm_size" {
  description = "VM size for AKS nodes"
  type        = string
  default     = "Standard_D2s_v3"
}

variable "max_node_count" {
  description = "Maximum number of nodes in the default node pool"
  type        = number
  default     = 10
}

variable "min_node_count" {
  description = "Minimum number of nodes in the default node pool"
  type        = number
  default     = 1
}

variable "enable_spot_instances" {
  description = "Enable spot instances for cost optimization"
  type        = bool
  default     = false
}

# AI/ML node pool variables
variable "enable_ai_node_pool" {
  description = "Enable dedicated node pool for AI/ML workloads"
  type        = bool
  default     = true
}

variable "ai_node_vm_size" {
  description = "VM size for AI/ML nodes (GPU-enabled)"
  type        = string
  default     = "Standard_NC6s_v3"
}

variable "ai_node_count" {
  description = "Number of nodes in AI/ML node pool"
  type        = number
  default     = 1
}

# Security variables
variable "key_vault_id" {
  description = "ID of the Key Vault"
  type        = string
}

variable "user_assigned_identity_id" {
  description = "ID of the user assigned managed identity"
  type        = string
}

variable "user_assigned_identity_principal_id" {
  description = "Principal ID of the user assigned managed identity"
  type        = string
}

variable "container_registry_id" {
  description = "ID of the container registry"
  type        = string
}

variable "log_analytics_workspace_id" {
  description = "ID of the Log Analytics workspace"
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
