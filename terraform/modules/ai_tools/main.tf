# Local for workload identity configuration
locals {
  workload_identity_enabled = var.enable_workload_identity && var.workload_identity_client_id != null

  # ServiceAccount annotations for Azure Workload Identity
  workload_identity_annotations = local.workload_identity_enabled ? {
    "azure.workload.identity/client-id" = var.workload_identity_client_id
  } : {}

  # Pod labels for Azure Workload Identity
  workload_identity_labels = local.workload_identity_enabled ? {
    "azure.workload.identity/use" = "true"
  } : {}

  # AGC configuration
  agc_enabled = var.agc_gateway_name != null
}

# Random passwords for secure defaults
resource "random_password" "jupyter_admin_password" {
  length  = 16
  special = true
}

resource "random_password" "jupyter_proxy_secret_token" {
  length  = 32
  special = false
}

# AI Tools namespace
resource "kubernetes_namespace" "ai_tools" {
  metadata {
    name = var.ai_tools_namespace
    labels = {
      name = var.ai_tools_namespace
    }
  }
}

# JupyterHub for data science workflows
resource "helm_release" "jupyterhub" {
  count = var.enable_jupyter_hub ? 1 : 0

  name       = "jupyterhub"
  repository = "https://jupyterhub.github.io/helm-chart/"
  chart      = "jupyterhub"
  version    = "3.1.0"
  namespace  = kubernetes_namespace.ai_tools.metadata[0].name

  values = [
    yamlencode({
      hub = {
        # Azure Workload Identity
        serviceAccount = {
          annotations = local.workload_identity_annotations
        }
        extraLabels = local.workload_identity_labels

        config = {
          JupyterHub = {
            admin_access        = true
            authenticator_class = "dummy"
          }
          DummyAuthenticator = {
            password = var.jupyter_admin_password != null ? var.jupyter_admin_password : random_password.jupyter_admin_password.result
          }
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

        service = {
          type = "ClusterIP"
        }

        ingress = {
          enabled     = var.enable_jupyter_ingress
          annotations = var.jupyter_ingress_annotations
          hosts       = var.jupyter_ingress_hosts
          tls         = var.jupyter_ingress_tls
        }
      }

      proxy = {
        secretToken = var.jupyter_proxy_secret_token != null ? var.jupyter_proxy_secret_token : random_password.jupyter_proxy_secret_token.result

        service = {
          type = "ClusterIP"
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

      singleuser = {
        image = {
          name = var.jupyter_notebook_image
          tag  = var.jupyter_notebook_tag
        }

        defaultUrl = "/lab"

        cpu = {
          limit     = var.jupyter_user_cpu_limit
          guarantee = var.jupyter_user_cpu_guarantee
        }

        memory = {
          limit     = var.jupyter_user_memory_limit
          guarantee = var.jupyter_user_memory_guarantee
        }

        storage = {
          dynamic = {
            storageClass = "managed-csi"
          }
          capacity = var.jupyter_user_storage_capacity
        }

        # GPU support for AI/ML workloads
        extraResource = var.enable_gpu_support ? {
          limits = {
            "nvidia.com/gpu" = var.jupyter_gpu_limit
          }
        } : {}

        # Node selector for AI node pool
        nodeSelector = var.enable_gpu_support ? {
          "node-type" = "ai"
        } : {}

        # Tolerations for AI node pool
        extraTolerations = var.enable_gpu_support ? [
          {
            key      = "nvidia.com/gpu"
            operator = "Equal"
            value    = "true"
            effect   = "NoSchedule"
          }
        ] : []
      }

      scheduling = {
        userScheduler = {
          enabled = true
        }
      }
    })
  ]

  depends_on = [kubernetes_namespace.ai_tools]
}

# MLflow for ML lifecycle management
resource "helm_release" "mlflow" {
  count = var.enable_mlflow ? 1 : 0

  name       = "mlflow"
  repository = "https://community-charts.github.io/helm-charts"
  chart      = "mlflow"
  version    = "0.7.19"
  namespace  = kubernetes_namespace.ai_tools.metadata[0].name

  values = [
    yamlencode({
      image = {
        repository = "python"
        tag        = "3.9-slim"
      }

      service = {
        type = "ClusterIP"
        port = 5000
      }

      ingress = {
        enabled     = var.enable_mlflow_ingress
        annotations = var.mlflow_ingress_annotations
        hosts       = var.mlflow_ingress_hosts
        tls         = var.mlflow_ingress_tls
      }

      resources = {
        limits = {
          cpu    = "1000m"
          memory = "2Gi"
        }
        requests = {
          cpu    = "500m"
          memory = "1Gi"
        }
      }

      persistence = {
        enabled      = true
        storageClass = "managed-csi"
        size         = var.mlflow_storage_size
      }

      # PostgreSQL backend for MLflow
      postgresql = {
        enabled = true
        auth = {
          postgresPassword = var.mlflow_db_password
          database         = "mlflow"
        }
        primary = {
          persistence = {
            enabled      = true
            storageClass = "managed-csi"
            size         = "20Gi"
          }
        }
      }

      # MinIO for artifact storage
      minio = {
        enabled = true
        auth = {
          rootUser     = "admin"
          rootPassword = var.mlflow_minio_password
        }
        persistence = {
          enabled      = true
          storageClass = "managed-csi"
          size         = var.mlflow_artifact_storage_size
        }
      }
    })
  ]

  depends_on = [kubernetes_namespace.ai_tools]
}

# NVIDIA GPU Operator (if GPU support is enabled)
resource "helm_release" "gpu_operator" {
  count = var.enable_gpu_support ? 1 : 0

  name             = "gpu-operator"
  repository       = "https://nvidia.github.io/gpu-operator"
  chart            = "gpu-operator"
  version          = "v23.9.1"
  namespace        = "gpu-operator"
  create_namespace = true

  values = [
    yamlencode({
      operator = {
        defaultRuntime = "containerd"
        resources = {
          limits = {
            cpu    = "500m"
            memory = "350Mi"
          }
          requests = {
            cpu    = "200m"
            memory = "100Mi"
          }
        }
      }

      driver = {
        enabled = true
        resources = {
          limits = {
            cpu    = "300m"
            memory = "512Mi"
          }
          requests = {
            cpu    = "100m"
            memory = "256Mi"
          }
        }
      }

      toolkit = {
        enabled = true
        resources = {
          limits = {
            cpu    = "250m"
            memory = "256Mi"
          }
          requests = {
            cpu    = "100m"
            memory = "128Mi"
          }
        }
      }

      devicePlugin = {
        enabled = true
        resources = {
          limits = {
            cpu    = "300m"
            memory = "300Mi"
          }
          requests = {
            cpu    = "100m"
            memory = "200Mi"
          }
        }
      }

      dcgmExporter = {
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

      gfd = {
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

      migManager = {
        enabled = false
      }

      nodeStatusExporter = {
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
    })
  ]
}

# Kubeflow (optional, resource intensive)
resource "helm_release" "kubeflow" {
  count = var.enable_kubeflow ? 1 : 0

  name             = "kubeflow"
  repository       = "https://kubeflow.github.io/manifests"
  chart            = "kubeflow"
  version          = "1.7.0"
  namespace        = "kubeflow"
  create_namespace = true
  timeout          = 1200 # 20 minutes

  values = [
    yamlencode({
      # Kubeflow configuration with resource limits
      # This is a simplified configuration
      # Full Kubeflow deployment requires more complex setup

      # Central Dashboard
      centralDashboard = {
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

      # Kubeflow Pipelines
      pipelines = {
        resources = {
          limits = {
            cpu    = "1000m"
            memory = "1Gi"
          }
          requests = {
            cpu    = "500m"
            memory = "512Mi"
          }
        }
      }

      # Notebook Controller
      notebookController = {
        resources = {
          limits = {
            cpu    = "300m"
            memory = "256Mi"
          }
          requests = {
            cpu    = "100m"
            memory = "128Mi"
          }
        }
      }
    })
  ]

  depends_on = [kubernetes_namespace.ai_tools]
}

# =============================================================================
# Application Gateway for Containers (AGC) HTTPRoutes for AI Tools
# =============================================================================
# HTTPRoute provides routing configuration for AGC Gateway API
# This is the preferred routing method for AGC (vs traditional Ingress)

# HTTPRoute for JupyterHub
resource "kubernetes_manifest" "jupyterhub_httproute" {
  count = local.agc_enabled && var.enable_jupyter_hub && var.enable_jupyter_ingress ? 1 : 0

  manifest = {
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "HTTPRoute"
    metadata = {
      name      = "jupyterhub"
      namespace = kubernetes_namespace.ai_tools.metadata[0].name
    }
    spec = {
      parentRefs = [
        {
          name      = var.agc_gateway_name
          namespace = var.agc_gateway_namespace
        }
      ]
      hostnames = var.jupyter_ingress_hosts
      rules = [
        {
          matches = [
            {
              path = {
                type  = "PathPrefix"
                value = "/"
              }
            }
          ]
          backendRefs = [
            {
              name = "proxy-public"
              port = 80
            }
          ]
        }
      ]
    }
  }

  depends_on = [helm_release.jupyterhub]
}

# HTTPRoute for MLflow
resource "kubernetes_manifest" "mlflow_httproute" {
  count = local.agc_enabled && var.enable_mlflow && var.enable_mlflow_ingress ? 1 : 0

  manifest = {
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "HTTPRoute"
    metadata = {
      name      = "mlflow"
      namespace = kubernetes_namespace.ai_tools.metadata[0].name
    }
    spec = {
      parentRefs = [
        {
          name      = var.agc_gateway_name
          namespace = var.agc_gateway_namespace
        }
      ]
      hostnames = var.mlflow_ingress_hosts
      rules = [
        {
          matches = [
            {
              path = {
                type  = "PathPrefix"
                value = "/"
              }
            }
          ]
          backendRefs = [
            {
              name = "mlflow"
              port = 5000
            }
          ]
        }
      ]
    }
  }

  depends_on = [helm_release.mlflow]
}
