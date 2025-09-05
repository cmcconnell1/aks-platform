output "argocd_namespace" {
  description = "Name of the ArgoCD namespace"
  value       = kubernetes_namespace.argocd.metadata[0].name
}

output "argocd_server_url" {
  description = "ArgoCD server URL"
  value       = "https://${var.argocd_domain}"
}

output "argocd_admin_password" {
  description = "ArgoCD admin password"
  value       = try(base64decode(data.kubernetes_secret.argocd_initial_admin_secret.data["password"]), "")
  sensitive   = true
}

output "argocd_release_name" {
  description = "Name of the ArgoCD Helm release"
  value       = helm_release.argocd.name
}
