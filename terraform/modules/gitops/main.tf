# ArgoCD namespace
resource "kubernetes_namespace" "argocd" {
  metadata {
    name = var.argocd_namespace
    labels = {
      name        = var.argocd_namespace
      environment = var.environment
    }
  }
}

# Data source to get ArgoCD initial admin secret
data "kubernetes_secret" "argocd_initial_admin_secret" {
  metadata {
    name      = "argocd-initial-admin-secret"
    namespace = kubernetes_namespace.argocd.metadata[0].name
  }

  depends_on = [helm_release.argocd]
}

# ArgoCD installation using Helm
resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = "5.51.6"
  namespace  = kubernetes_namespace.argocd.metadata[0].name

  # ArgoCD server configuration
  values = [
    yamlencode({
      global = {
        domain = var.argocd_domain != null ? var.argocd_domain : "argocd.${var.cluster_name}.local"
      }

      configs = {
        params = {
          "server.insecure" = var.enable_insecure_mode
        }

        cm = {
          "url" = var.argocd_domain != null ? "https://${var.argocd_domain}" : "https://argocd.${var.cluster_name}.local"

          # Enable OIDC authentication if configured
          "oidc.config" = var.enable_oidc ? yamlencode({
            name            = "Azure AD"
            issuer          = "https://login.microsoftonline.com/${var.tenant_id}/v2.0"
            clientId        = var.oidc_client_id
            clientSecret    = var.oidc_client_secret
            requestedScopes = ["openid", "profile", "email", "groups"]
            requestedIDTokenClaims = {
              groups = {
                essential = true
              }
            }
          }) : ""

          # Repository configuration
          "repositories" = var.git_repositories != null ? yamlencode(var.git_repositories) : ""
        }

        rbac = {
          "policy.default" = "role:readonly"
          "policy.csv"     = var.rbac_policy
        }
      }

      server = {
        replicas = var.server_replicas

        service = {
          type        = var.service_type
          annotations = var.service_annotations
        }

        ingress = {
          enabled     = var.enable_ingress
          annotations = var.ingress_annotations
          hosts       = var.ingress_hosts
          tls         = var.ingress_tls
        }

        # Resource limits
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

        # High availability configuration
        affinity = {
          podAntiAffinity = {
            preferredDuringSchedulingIgnoredDuringExecution = [
              {
                weight = 100
                podAffinityTerm = {
                  labelSelector = {
                    matchLabels = {
                      "app.kubernetes.io/name" = "argocd-server"
                    }
                  }
                  topologyKey = "kubernetes.io/hostname"
                }
              }
            ]
          }
        }
      }

      controller = {
        replicas = var.controller_replicas

        # Resource limits
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

      repoServer = {
        replicas = var.repo_server_replicas

        # Resource limits
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

      applicationSet = {
        enabled = var.enable_application_set

        # Resource limits
        resources = {
          limits = {
            cpu    = "100m"
            memory = "128Mi"
          }
          requests = {
            cpu    = "50m"
            memory = "64Mi"
          }
        }
      }

      notifications = {
        enabled = var.enable_notifications
      }

      # Redis for caching
      redis = {
        enabled = true

        # Resource limits
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

  depends_on = [kubernetes_namespace.argocd]
}

# ArgoCD CLI configuration secret
resource "kubernetes_secret" "argocd_cli_config" {
  count = var.create_cli_config ? 1 : 0

  metadata {
    name      = "argocd-cli-config"
    namespace = kubernetes_namespace.argocd.metadata[0].name
  }

  data = {
    config = yamlencode({
      contexts = {
        "${var.cluster_name}" = {
          server = "argocd-server.${kubernetes_namespace.argocd.metadata[0].name}.svc.cluster.local"
        }
      }
      "current-context" = var.cluster_name
    })
  }
}

# Initial ArgoCD application for app-of-apps pattern
resource "kubernetes_manifest" "app_of_apps" {
  count = var.enable_app_of_apps ? 1 : 0

  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name       = "app-of-apps"
      namespace  = kubernetes_namespace.argocd.metadata[0].name
      finalizers = ["resources-finalizer.argocd.argoproj.io"]
    }
    spec = {
      project = "default"
      source = {
        repoURL        = var.app_of_apps_repo_url
        targetRevision = var.app_of_apps_target_revision
        path           = var.app_of_apps_path
      }
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = kubernetes_namespace.argocd.metadata[0].name
      }
      syncPolicy = {
        automated = {
          prune    = true
          selfHeal = true
        }
        syncOptions = [
          "CreateNamespace=true"
        ]
      }
    }
  }

  depends_on = [helm_release.argocd]
}
