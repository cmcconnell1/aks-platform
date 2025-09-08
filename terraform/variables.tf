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

variable "app_gateway_subnet_address_prefix" {
  description = "Address prefix for Application Gateway subnet"
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

# Application Gateway variables
variable "enable_application_gateway" {
  description = "Enable Application Gateway with AGIC"
  type        = bool
  default     = true
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
