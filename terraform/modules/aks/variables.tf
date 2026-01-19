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

# Network configuration
variable "service_cidr" {
  description = "CIDR for Kubernetes services"
  type        = string
  default     = "10.2.0.0/24"
}

variable "dns_service_ip" {
  description = "IP address for Kubernetes DNS service"
  type        = string
  default     = "10.2.0.10"
}

# OS disk configuration
variable "system_os_disk_size_gb" {
  description = "OS disk size in GB for system node pool"
  type        = number
  default     = 100
}

variable "user_os_disk_size_gb" {
  description = "OS disk size in GB for user node pool"
  type        = number
  default     = 100
}

variable "ai_os_disk_size_gb" {
  description = "OS disk size in GB for AI node pool"
  type        = number
  default     = 200
}

# Upgrade settings
variable "system_max_surge" {
  description = "Max surge for system node pool upgrades"
  type        = string
  default     = "10%"
}

variable "user_max_surge" {
  description = "Max surge for user node pool upgrades"
  type        = string
  default     = "33%"
}

variable "ai_max_surge" {
  description = "Max surge for AI node pool upgrades"
  type        = string
  default     = "33%"
}

# Security settings
variable "enable_run_command" {
  description = "Enable run command on AKS cluster (disable for production security)"
  type        = bool
  default     = false
}

# Autoscaler profile
variable "autoscaler_profile" {
  description = "Autoscaler profile configuration"
  type = object({
    balance_similar_node_groups      = optional(bool, false)
    expander                         = optional(string, "random")
    max_graceful_termination_sec     = optional(string, "600")
    max_node_provisioning_time       = optional(string, "15m")
    max_unready_nodes                = optional(number, 3)
    max_unready_percentage           = optional(number, 45)
    new_pod_scale_up_delay           = optional(string, "10s")
    scale_down_delay_after_add       = optional(string, "10m")
    scale_down_delay_after_delete    = optional(string, "10s")
    scale_down_delay_after_failure   = optional(string, "3m")
    scan_interval                    = optional(string, "10s")
    scale_down_unneeded              = optional(string, "10m")
    scale_down_unready               = optional(string, "20m")
    scale_down_utilization_threshold = optional(string, "0.5")
  })
  default = {}
}
