# Prometheus and Grafana monitoring stack using Helm
resource "kubernetes_namespace" "monitoring" {
  metadata {
    name = var.monitoring_namespace
    labels = {
      name = var.monitoring_namespace
    }
  }
}

# Prometheus using kube-prometheus-stack
resource "helm_release" "prometheus" {
  name       = "prometheus"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  version    = "55.5.0"
  namespace  = kubernetes_namespace.monitoring.metadata[0].name

  values = [
    yamlencode({
      prometheus = {
        prometheusSpec = {
          retention = var.prometheus_retention
          storageSpec = {
            volumeClaimTemplate = {
              spec = {
                storageClassName = "managed-csi"
                accessModes      = ["ReadWriteOnce"]
                resources = {
                  requests = {
                    storage = var.prometheus_storage_size
                  }
                }
              }
            }
          }
          resources = {
            limits = {
              cpu    = "2000m"
              memory = "4Gi"
            }
            requests = {
              cpu    = "1000m"
              memory = "2Gi"
            }
          }
        }
      }

      grafana = {
        enabled = true
        adminPassword = var.grafana_admin_password
        
        service = {
          type = "ClusterIP"
        }
        
        ingress = {
          enabled = var.enable_grafana_ingress
          annotations = var.grafana_ingress_annotations
          hosts = var.grafana_ingress_hosts
          tls = var.grafana_ingress_tls
        }
        
        persistence = {
          enabled = true
          storageClassName = "managed-csi"
          size = var.grafana_storage_size
        }
        
        resources = {
          limits = {
            cpu    = "500m"
            memory = "512Mi"
          }
          requests = {
            cpu    = "250m"
            memory = "256Mi"
          }
        }
        
        # Default dashboards
        defaultDashboardsEnabled = true
        
        # Additional dashboards
        dashboardProviders = {
          "dashboardproviders.yaml" = {
            apiVersion = 1
            providers = [
              {
                name = "default"
                orgId = 1
                folder = ""
                type = "file"
                disableDeletion = false
                editable = true
                options = {
                  path = "/var/lib/grafana/dashboards/default"
                }
              }
            ]
          }
        }
      }

      alertmanager = {
        enabled = var.enable_alertmanager
        
        alertmanagerSpec = {
          storage = {
            volumeClaimTemplate = {
              spec = {
                storageClassName = "managed-csi"
                accessModes      = ["ReadWriteOnce"]
                resources = {
                  requests = {
                    storage = var.alertmanager_storage_size
                  }
                }
              }
            }
          }
          
          resources = {
            limits = {
              cpu    = "200m"
              memory = "256Mi"
            }
            requests = {
              cpu    = "100m"
              memory = "128Mi"
            }
          }
        }
      }

      # Node exporter for node metrics
      nodeExporter = {
        enabled = true
      }

      # Kube-state-metrics for Kubernetes object metrics
      kubeStateMetrics = {
        enabled = true
      }
    })
  ]

  depends_on = [kubernetes_namespace.monitoring]
}

# Loki for log aggregation (optional)
resource "helm_release" "loki" {
  count = var.enable_loki ? 1 : 0

  name       = "loki"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "loki-stack"
  version    = "2.9.11"
  namespace  = kubernetes_namespace.monitoring.metadata[0].name

  values = [
    yamlencode({
      loki = {
        enabled = true
        persistence = {
          enabled = true
          storageClassName = "managed-csi"
          size = var.loki_storage_size
        }
        
        resources = {
          limits = {
            cpu    = "500m"
            memory = "1Gi"
          }
          requests = {
            cpu    = "250m"
            memory = "512Mi"
          }
        }
      }

      promtail = {
        enabled = true
        
        resources = {
          limits = {
            cpu    = "200m"
            memory = "256Mi"
          }
          requests = {
            cpu    = "100m"
            memory = "128Mi"
          }
        }
      }

      fluent-bit = {
        enabled = false
      }

      grafana = {
        enabled = false # Use the Grafana from prometheus stack
      }
    })
  ]

  depends_on = [helm_release.prometheus]
}

# Jaeger for distributed tracing (optional)
resource "helm_release" "jaeger" {
  count = var.enable_jaeger ? 1 : 0

  name       = "jaeger"
  repository = "https://jaegertracing.github.io/helm-charts"
  chart      = "jaeger"
  version    = "0.71.11"
  namespace  = kubernetes_namespace.monitoring.metadata[0].name

  values = [
    yamlencode({
      provisionDataStore = {
        cassandra = false
        elasticsearch = true
      }

      storage = {
        type = "elasticsearch"
        elasticsearch = {
          host = "elasticsearch-master"
          port = 9200
        }
      }

      agent = {
        resources = {
          limits = {
            cpu    = "200m"
            memory = "256Mi"
          }
          requests = {
            cpu    = "100m"
            memory = "128Mi"
          }
        }
      }

      collector = {
        resources = {
          limits = {
            cpu    = "500m"
            memory = "512Mi"
          }
          requests = {
            cpu    = "250m"
            memory = "256Mi"
          }
        }
      }

      query = {
        resources = {
          limits = {
            cpu    = "300m"
            memory = "256Mi"
          }
          requests = {
            cpu    = "150m"
            memory = "128Mi"
          }
        }
      }
    })
  ]

  depends_on = [helm_release.prometheus]
}
