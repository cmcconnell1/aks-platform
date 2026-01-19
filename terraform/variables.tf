# Core variables
variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "location" {
  description = "Azure region for resources"
  type        = string
  default     = "East US"
}

variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "aks-platform"
}

# Resource naming
variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
  default     = null
}

# Networking variables
variable "vnet_address_space" {
  description = "Address space for the virtual network"
  type        = list(string)
  default     = ["10.0.0.0/16"]
}

variable "aks_subnet_address_prefix" {
  description = "Address prefix for AKS subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "agc_subnet_address_prefix" {
  description = "Address prefix for Application Gateway for Containers (AGC) subnet"
  type        = string
  default     = "10.0.2.0/24"
}

variable "private_endpoint_subnet_address_prefix" {
  description = "Address prefix for private endpoints subnet"
  type        = string
  default     = "10.0.3.0/24"
}

# AKS variables
variable "kubernetes_version" {
  description = "Kubernetes version for AKS cluster"
  type        = string
  default     = "1.28.5" # Pinned to stable version for consistency
}

variable "aks_node_count" {
  description = "Initial number of nodes in the default node pool"
  type        = number
  default     = 2
}

variable "aks_node_vm_size" {
  description = "VM size for AKS nodes"
  type        = string
  default     = "Standard_D2s_v3"
}

variable "aks_max_node_count" {
  description = "Maximum number of nodes in the default node pool"
  type        = number
  default     = 10
}

variable "aks_min_node_count" {
  description = "Minimum number of nodes in the default node pool"
  type        = number
  default     = 1
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

variable "enable_private_endpoints" {
  description = "Enable private endpoints for Azure services"
  type        = bool
  default     = true
}

variable "enable_run_command" {
  description = "Enable AKS run command (disable for production security hardening)"
  type        = bool
  default     = false
}

# SSL Certificate variables
variable "create_demo_ssl_certificate" {
  description = "Create a demo SSL certificate for testing"
  type        = bool
  default     = false
}

variable "ssl_certificate_subject" {
  description = "Subject for SSL certificate"
  type        = string
  default     = "aks-platform.local"
}

variable "ssl_certificate_dns_names" {
  description = "DNS names for SSL certificate"
  type        = list(string)
  default     = ["aks-platform.local", "*.aks-platform.local"]
}

# Application Gateway for Containers (AGC) variables
variable "enable_agc" {
  description = "Enable Application Gateway for Containers (AGC) with ALB Controller"
  type        = bool
  default     = true
}

variable "create_default_gateway" {
  description = "Create a default Gateway resource for AGC"
  type        = bool
  default     = true
}

variable "enable_agc_https" {
  description = "Enable HTTPS listener on AGC Gateway"
  type        = bool
  default     = true
}

variable "agc_tls_certificate_refs" {
  description = "TLS certificate references for AGC HTTPS listener (cert-manager secrets)"
  type = list(object({
    name      = string
    namespace = optional(string)
  }))
  default = []
}

# Let's Encrypt / cert-manager variables
variable "enable_cert_manager" {
  description = "Enable cert-manager for automatic SSL certificate management"
  type        = bool
  default     = false
}

variable "letsencrypt_email" {
  description = "Email address for Let's Encrypt certificate registration"
  type        = string
  default     = ""
}

variable "enable_letsencrypt_staging" {
  description = "Enable Let's Encrypt staging environment (for testing)"
  type        = bool
  default     = true
}

variable "enable_letsencrypt_prod" {
  description = "Enable Let's Encrypt production environment"
  type        = bool
  default     = false
}

# GitOps variables
variable "enable_argocd" {
  description = "Enable ArgoCD installation"
  type        = bool
  default     = true
}

variable "argocd_namespace" {
  description = "Namespace for ArgoCD"
  type        = string
  default     = "argocd"
}

# AI Tools variables
variable "enable_ai_tools" {
  description = "Enable AI/ML tools installation"
  type        = bool
  default     = true
}

variable "enable_jupyter_hub" {
  description = "Enable JupyterHub for data science workflows"
  type        = bool
  default     = true
}

variable "enable_mlflow" {
  description = "Enable MLflow for ML lifecycle management"
  type        = bool
  default     = true
}

variable "enable_kubeflow" {
  description = "Enable Kubeflow for ML pipelines"
  type        = bool
  default     = false # Resource intensive, disabled by default
}

# Monitoring variables
variable "enable_monitoring" {
  description = "Enable monitoring stack (Prometheus, Grafana)"
  type        = bool
  default     = true
}

variable "enable_logging" {
  description = "Enable centralized logging"
  type        = bool
  default     = true
}

# Cost optimization
variable "enable_spot_instances" {
  description = "Enable spot instances for cost optimization"
  type        = bool
  default     = false
}

# Tags
variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Project     = "AKS-GitOps"
    ManagedBy   = "Terraform"
    Environment = "dev"
  }
}

# =============================================================================
# AKS Network Configuration
# =============================================================================

variable "aks_service_cidr" {
  description = "CIDR for Kubernetes services"
  type        = string
  default     = "10.2.0.0/24"
}

variable "aks_dns_service_ip" {
  description = "IP address for Kubernetes DNS service (must be within service_cidr)"
  type        = string
  default     = "10.2.0.10"
}

# =============================================================================
# AKS Node Pool Configuration
# =============================================================================

variable "system_node_pool_os_disk_size_gb" {
  description = "OS disk size in GB for system node pool"
  type        = number
  default     = 100
}

variable "user_node_pool_os_disk_size_gb" {
  description = "OS disk size in GB for user node pool"
  type        = number
  default     = 100
}

variable "ai_node_pool_os_disk_size_gb" {
  description = "OS disk size in GB for AI/ML node pool"
  type        = number
  default     = 200
}

variable "system_node_pool_max_surge" {
  description = "Max surge setting for system node pool upgrades (e.g., '10%' or '1')"
  type        = string
  default     = "10%"
}

variable "user_node_pool_max_surge" {
  description = "Max surge setting for user node pool upgrades (e.g., '33%' or '1')"
  type        = string
  default     = "33%"
}

variable "ai_node_pool_max_surge" {
  description = "Max surge setting for AI/ML node pool upgrades (e.g., '33%' or '1')"
  type        = string
  default     = "33%"
}

# =============================================================================
# AKS Autoscaler Profile
# =============================================================================

variable "aks_autoscaler_profile" {
  description = "Autoscaler profile configuration for AKS cluster"
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

# =============================================================================
# Storage Configuration
# =============================================================================

variable "default_storage_class" {
  description = "Default Kubernetes storage class for persistent volumes"
  type        = string
  default     = "managed-csi"
}

# =============================================================================
# Helm Chart Versions
# =============================================================================

variable "helm_chart_versions" {
  description = "Versions for Helm charts used in the platform"
  type = object({
    cert_manager     = optional(string, "v1.13.2")
    argocd           = optional(string, "5.51.6")
    prometheus_stack = optional(string, "55.5.0")
    loki             = optional(string, "2.9.11")
    promtail         = optional(string, "6.15.3")
    jaeger           = optional(string, "0.71.11")
    jupyterhub       = optional(string, "3.1.0")
    mlflow           = optional(string, "0.7.19")
  })
  default = {}
}

# =============================================================================
# Monitoring Configuration
# =============================================================================

variable "prometheus_storage_size" {
  description = "Storage size for Prometheus"
  type        = string
  default     = "50Gi"
}

variable "prometheus_retention" {
  description = "Data retention period for Prometheus"
  type        = string
  default     = "30d"
}

variable "grafana_storage_size" {
  description = "Storage size for Grafana"
  type        = string
  default     = "10Gi"
}

variable "alertmanager_storage_size" {
  description = "Storage size for Alertmanager"
  type        = string
  default     = "10Gi"
}

variable "loki_storage_size" {
  description = "Storage size for Loki log aggregation"
  type        = string
  default     = "50Gi"
}

# =============================================================================
# Sensitive Credentials (NO DEFAULTS - must be provided)
# =============================================================================

variable "grafana_admin_password" {
  description = "Admin password for Grafana (required, no default for security)"
  type        = string
  sensitive   = true
  default     = null
}

variable "mlflow_db_password" {
  description = "Database password for MLflow (required, no default for security)"
  type        = string
  sensitive   = true
  default     = null
}

variable "mlflow_minio_password" {
  description = "MinIO password for MLflow artifacts (required, no default for security)"
  type        = string
  sensitive   = true
  default     = null
}

# =============================================================================
# Application Gateway for Containers (AGC) Configuration
# =============================================================================

variable "alb_controller_version" {
  description = "Version of the ALB Controller Helm chart"
  type        = string
  default     = "1.3.7"
}

variable "gateway_api_version" {
  description = "Version of the Gateway API Helm chart"
  type        = string
  default     = "1.2.0"
}
