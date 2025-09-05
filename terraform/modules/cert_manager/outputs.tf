output "cert_manager_namespace" {
  description = "Namespace where cert-manager is installed"
  value       = kubernetes_namespace.cert_manager.metadata[0].name
}

output "letsencrypt_staging_issuer" {
  description = "Name of the Let's Encrypt staging issuer"
  value       = var.enable_letsencrypt_staging ? "letsencrypt-staging" : null
}

output "letsencrypt_prod_issuer" {
  description = "Name of the Let's Encrypt production issuer"
  value       = var.enable_letsencrypt_prod ? "letsencrypt-prod" : null
}

output "letsencrypt_dns01_issuer" {
  description = "Name of the Let's Encrypt DNS01 issuer"
  value       = var.enable_dns01_solver ? "letsencrypt-dns01" : null
}

output "cert_manager_ready" {
  description = "Indicates if cert-manager is ready"
  value       = helm_release.cert_manager.status == "deployed"
}
