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
  description = "ID of the subnet for AGC association (must have Microsoft.ServiceNetworking/trafficControllers delegation)"
  type        = string
}

variable "subscription_id" {
  description = "Azure subscription ID"
  type        = string
}

variable "aks_oidc_issuer_url" {
  description = "OIDC issuer URL from the AKS cluster for workload identity"
  type        = string
}

# ALB Controller Configuration
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

# Gateway Configuration
variable "create_default_gateway" {
  description = "Create a default Gateway resource"
  type        = bool
  default     = true
}

variable "gateway_namespace" {
  description = "Namespace for the Gateway resource"
  type        = string
  default     = "default"
}

variable "enable_https" {
  description = "Enable HTTPS listener on the Gateway"
  type        = bool
  default     = true
}

variable "tls_certificate_refs" {
  description = "TLS certificate references for HTTPS listener"
  type = list(object({
    name      = string
    namespace = optional(string)
  }))
  default = []
}

# SSL/TLS Configuration (for cert-manager integration)
variable "ssl_certificate_name" {
  description = "Name of the SSL certificate (used with cert-manager)"
  type        = string
  default     = null
}

variable "ssl_certificate_namespace" {
  description = "Namespace where the SSL certificate secret is stored"
  type        = string
  default     = "default"
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
