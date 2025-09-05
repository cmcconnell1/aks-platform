output "ai_tools_namespace" {
  description = "Name of the AI tools namespace"
  value       = kubernetes_namespace.ai_tools.metadata[0].name
}

output "jupyter_hub_url" {
  description = "JupyterHub URL"
  value       = var.enable_jupyter_hub ? "https://${var.jupyter_ingress_hosts[0]}" : null
}

output "mlflow_url" {
  description = "MLflow URL"
  value       = var.enable_mlflow ? "https://${var.mlflow_ingress_hosts[0]}" : null
}

output "jupyter_admin_password" {
  description = "JupyterHub admin password"
  value       = var.enable_jupyter_hub ? var.jupyter_admin_password : null
  sensitive   = true
}

output "mlflow_db_password" {
  description = "MLflow database password"
  value       = var.enable_mlflow ? var.mlflow_db_password : null
  sensitive   = true
}

output "gpu_operator_enabled" {
  description = "Whether GPU operator is enabled"
  value       = var.enable_gpu_support
}

output "kubeflow_enabled" {
  description = "Whether Kubeflow is enabled"
  value       = var.enable_kubeflow
}
