variable "monitoring_namespace" {
  description = "Namespace for monitoring components"
  type        = string
  default     = "monitoring"
}

# Prometheus Configuration
variable "prometheus_retention" {
  description = "Prometheus data retention period"
  type        = string
  default     = "30d"
}

variable "prometheus_storage_size" {
  description = "Storage size for Prometheus"
  type        = string
  default     = "50Gi"
}

# Grafana Configuration
variable "grafana_admin_password" {
  description = "Admin password for Grafana"
  type        = string
  default     = "admin123"
  sensitive   = true
}

variable "enable_grafana_ingress" {
  description = "Enable ingress for Grafana"
  type        = bool
  default     = true
}

variable "grafana_ingress_annotations" {
  description = "Annotations for Grafana ingress"
  type        = map(string)
  default = {
    "kubernetes.io/ingress.class"                    = "azure/application-gateway"
    "appgw.ingress.kubernetes.io/ssl-redirect"       = "true"
    "appgw.ingress.kubernetes.io/backend-protocol"   = "http"
  }
}

variable "grafana_ingress_hosts" {
  description = "Hosts for Grafana ingress"
  type        = list(string)
  default     = ["grafana.local"]
}

variable "grafana_ingress_tls" {
  description = "TLS configuration for Grafana ingress"
  type        = list(object({
    secretName = string
    hosts      = list(string)
  }))
  default = []
}

variable "grafana_storage_size" {
  description = "Storage size for Grafana"
  type        = string
  default     = "10Gi"
}

# Alertmanager Configuration
variable "enable_alertmanager" {
  description = "Enable Alertmanager"
  type        = bool
  default     = true
}

variable "alertmanager_storage_size" {
  description = "Storage size for Alertmanager"
  type        = string
  default     = "10Gi"
}

# Loki Configuration
variable "enable_loki" {
  description = "Enable Loki for log aggregation"
  type        = bool
  default     = true
}

variable "loki_storage_size" {
  description = "Storage size for Loki"
  type        = string
  default     = "50Gi"
}

# Jaeger Configuration
variable "enable_jaeger" {
  description = "Enable Jaeger for distributed tracing"
  type        = bool
  default     = false
}
