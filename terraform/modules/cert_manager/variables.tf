variable "cert_manager_namespace" {
  description = "Namespace for cert-manager"
  type        = string
  default     = "cert-manager"
}

variable "cert_manager_identity_client_id" {
  description = "Client ID of the managed identity for cert-manager"
  type        = string
}

variable "letsencrypt_email" {
  description = "Email address for Let's Encrypt registration"
  type        = string
}

variable "enable_letsencrypt_staging" {
  description = "Enable Let's Encrypt staging issuer"
  type        = bool
  default     = true
}

variable "enable_letsencrypt_prod" {
  description = "Enable Let's Encrypt production issuer"
  type        = bool
  default     = false
}

variable "enable_dns01_solver" {
  description = "Enable DNS01 solver for wildcard certificates"
  type        = bool
  default     = false
}

variable "subscription_id" {
  description = "Azure subscription ID"
  type        = string
  default     = null
}

variable "tenant_id" {
  description = "Azure tenant ID"
  type        = string
  default     = null
}

variable "dns_resource_group_name" {
  description = "Resource group name containing the DNS zone"
  type        = string
  default     = null
}

variable "dns_zone_name" {
  description = "DNS zone name for DNS01 challenges"
  type        = string
  default     = null
}

variable "create_example_certificate" {
  description = "Create an example certificate for testing"
  type        = bool
  default     = false
}

variable "certificate_dns_names" {
  description = "DNS names for the example certificate"
  type        = list(string)
  default     = []
}
