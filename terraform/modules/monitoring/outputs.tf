output "monitoring_namespace" {
  description = "Name of the monitoring namespace"
  value       = kubernetes_namespace.monitoring.metadata[0].name
}

output "prometheus_release_name" {
  description = "Name of the Prometheus Helm release"
  value       = helm_release.prometheus.name
}

output "prometheus_url" {
  description = "Internal URL for Prometheus"
  value       = "http://prometheus-kube-prometheus-prometheus.${kubernetes_namespace.monitoring.metadata[0].name}.svc.cluster.local:9090"
}

output "grafana_url" {
  description = "Internal URL for Grafana"
  value       = "http://prometheus-grafana.${kubernetes_namespace.monitoring.metadata[0].name}.svc.cluster.local"
}

output "grafana_admin_password" {
  description = "Admin password for Grafana"
  value       = var.grafana_admin_password
  sensitive   = true
}

output "alertmanager_url" {
  description = "Internal URL for Alertmanager"
  value       = var.enable_alertmanager ? "http://prometheus-kube-prometheus-alertmanager.${kubernetes_namespace.monitoring.metadata[0].name}.svc.cluster.local:9093" : null
}

output "loki_url" {
  description = "Internal URL for Loki"
  value       = var.enable_loki ? "http://loki.${kubernetes_namespace.monitoring.metadata[0].name}.svc.cluster.local:3100" : null
}

output "jaeger_url" {
  description = "Internal URL for Jaeger"
  value       = var.enable_jaeger ? "http://jaeger-query.${kubernetes_namespace.monitoring.metadata[0].name}.svc.cluster.local" : null
}
