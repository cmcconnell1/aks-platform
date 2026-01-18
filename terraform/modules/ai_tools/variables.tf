variable "ai_tools_namespace" {
  description = "Namespace for AI tools"
  type        = string
  default     = "ai-tools"
}

# JupyterHub Configuration
variable "enable_jupyter_hub" {
  description = "Enable JupyterHub deployment"
  type        = bool
  default     = true
}

variable "jupyter_admin_password" {
  description = "Admin password for JupyterHub (leave null to auto-generate)"
  type        = string
  default     = null
  sensitive   = true
}

variable "jupyter_proxy_secret_token" {
  description = "Secret token for JupyterHub proxy (leave null to auto-generate)"
  type        = string
  default     = null
  sensitive   = true
}

variable "jupyter_notebook_image" {
  description = "Docker image for Jupyter notebooks"
  type        = string
  default     = "jupyter/datascience-notebook:2024-01-08"
}

variable "jupyter_notebook_tag" {
  description = "Tag for Jupyter notebook image"
  type        = string
  default     = "latest"
}

variable "jupyter_user_cpu_limit" {
  description = "CPU limit per user"
  type        = string
  default     = "2"
}

variable "jupyter_user_cpu_guarantee" {
  description = "CPU guarantee per user"
  type        = string
  default     = "0.5"
}

variable "jupyter_user_memory_limit" {
  description = "Memory limit per user"
  type        = string
  default     = "4G"
}

variable "jupyter_user_memory_guarantee" {
  description = "Memory guarantee per user"
  type        = string
  default     = "1G"
}

variable "jupyter_user_storage_capacity" {
  description = "Storage capacity per user"
  type        = string
  default     = "10Gi"
}

variable "enable_jupyter_ingress" {
  description = "Enable ingress for JupyterHub"
  type        = bool
  default     = true
}

variable "jupyter_ingress_annotations" {
  description = "Annotations for JupyterHub ingress"
  type        = map(string)
  default = {
    "kubernetes.io/ingress.class"                  = "azure/application-gateway"
    "appgw.ingress.kubernetes.io/ssl-redirect"     = "true"
    "appgw.ingress.kubernetes.io/backend-protocol" = "http"
  }
}

variable "jupyter_ingress_hosts" {
  description = "Hosts for JupyterHub ingress"
  type        = list(string)
  default     = ["jupyter.local"]
}

variable "jupyter_ingress_tls" {
  description = "TLS configuration for JupyterHub ingress"
  type = list(object({
    secretName = string
    hosts      = list(string)
  }))
  default = []
}

# MLflow Configuration
variable "enable_mlflow" {
  description = "Enable MLflow deployment"
  type        = bool
  default     = true
}

variable "mlflow_storage_size" {
  description = "Storage size for MLflow"
  type        = string
  default     = "20Gi"
}

variable "mlflow_artifact_storage_size" {
  description = "Storage size for MLflow artifacts"
  type        = string
  default     = "50Gi"
}

variable "mlflow_db_password" {
  description = "Database password for MLflow (required - no default for security)"
  type        = string
  sensitive   = true
  # No default - must be provided explicitly for security
}

variable "mlflow_minio_password" {
  description = "MinIO password for MLflow artifacts (required - no default for security)"
  type        = string
  sensitive   = true
  # No default - must be provided explicitly for security
}

variable "enable_mlflow_ingress" {
  description = "Enable ingress for MLflow"
  type        = bool
  default     = true
}

variable "mlflow_ingress_annotations" {
  description = "Annotations for MLflow ingress"
  type        = map(string)
  default = {
    "kubernetes.io/ingress.class"                  = "azure/application-gateway"
    "appgw.ingress.kubernetes.io/ssl-redirect"     = "true"
    "appgw.ingress.kubernetes.io/backend-protocol" = "http"
  }
}

variable "mlflow_ingress_hosts" {
  description = "Hosts for MLflow ingress"
  type        = list(string)
  default     = ["mlflow.local"]
}

variable "mlflow_ingress_tls" {
  description = "TLS configuration for MLflow ingress"
  type = list(object({
    secretName = string
    hosts      = list(string)
  }))
  default = []
}

# GPU Configuration
variable "enable_gpu_support" {
  description = "Enable GPU support for AI workloads"
  type        = bool
  default     = true
}

variable "jupyter_gpu_limit" {
  description = "GPU limit per Jupyter user"
  type        = number
  default     = 1
}

# Kubeflow Configuration
variable "enable_kubeflow" {
  description = "Enable Kubeflow deployment"
  type        = bool
  default     = false
}
