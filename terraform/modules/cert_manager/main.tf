# Terraform configuration for cert-manager module
terraform {
  required_providers {
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.14"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.0"
    }
  }
}

# cert-manager namespace
resource "kubernetes_namespace" "cert_manager" {
  metadata {
    name = var.cert_manager_namespace
    labels = {
      name = var.cert_manager_namespace
    }
  }
}

# cert-manager CRDs
resource "kubectl_manifest" "cert_manager_crds" {
  for_each = toset([
    "https://github.com/cert-manager/cert-manager/releases/download/v1.13.2/cert-manager.crds.yaml"
  ])
  
  yaml_body = data.http.cert_manager_crds[each.key].response_body
  
  depends_on = [kubernetes_namespace.cert_manager]
}

data "http" "cert_manager_crds" {
  for_each = toset([
    "https://github.com/cert-manager/cert-manager/releases/download/v1.13.2/cert-manager.crds.yaml"
  ])
  
  url = each.key
}

# cert-manager Helm release
resource "helm_release" "cert_manager" {
  name       = "cert-manager"
  repository = "https://charts.jetstack.io"
  chart      = "cert-manager"
  version    = "v1.13.2"
  namespace  = kubernetes_namespace.cert_manager.metadata[0].name

  values = [
    yamlencode({
      installCRDs = false # We install them separately above
      
      global = {
        leaderElection = {
          namespace = kubernetes_namespace.cert_manager.metadata[0].name
        }
      }
      
      # Enable Azure Workload Identity
      serviceAccount = {
        annotations = {
          "azure.workload.identity/client-id" = var.cert_manager_identity_client_id
        }
      }
      
      podLabels = {
        "azure.workload.identity/use" = "true"
      }
      
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
      
      webhook = {
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
      
      cainjector = {
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
    })
  ]

  depends_on = [kubectl_manifest.cert_manager_crds]
}

# Let's Encrypt ClusterIssuer for staging
resource "kubectl_manifest" "letsencrypt_staging" {
  count = var.enable_letsencrypt_staging ? 1 : 0
  
  yaml_body = yamlencode({
    apiVersion = "cert-manager.io/v1"
    kind       = "ClusterIssuer"
    metadata = {
      name = "letsencrypt-staging"
    }
    spec = {
      acme = {
        server = "https://acme-staging-v02.api.letsencrypt.org/directory"
        email  = var.letsencrypt_email
        privateKeySecretRef = {
          name = "letsencrypt-staging"
        }
        solvers = [
          {
            http01 = {
              ingress = {
                class = "azure/application-gateway"
              }
            }
          }
        ]
      }
    }
  })

  depends_on = [helm_release.cert_manager]
}

# Let's Encrypt ClusterIssuer for production
resource "kubectl_manifest" "letsencrypt_prod" {
  count = var.enable_letsencrypt_prod ? 1 : 0
  
  yaml_body = yamlencode({
    apiVersion = "cert-manager.io/v1"
    kind       = "ClusterIssuer"
    metadata = {
      name = "letsencrypt-prod"
    }
    spec = {
      acme = {
        server = "https://acme-v02.api.letsencrypt.org/directory"
        email  = var.letsencrypt_email
        privateKeySecretRef = {
          name = "letsencrypt-prod"
        }
        solvers = [
          {
            http01 = {
              ingress = {
                class = "azure/application-gateway"
              }
            }
          }
        ]
      }
    }
  })

  depends_on = [helm_release.cert_manager]
}

# DNS01 solver for wildcard certificates (optional)
resource "kubectl_manifest" "letsencrypt_dns01" {
  count = var.enable_dns01_solver ? 1 : 0
  
  yaml_body = yamlencode({
    apiVersion = "cert-manager.io/v1"
    kind       = "ClusterIssuer"
    metadata = {
      name = "letsencrypt-dns01"
    }
    spec = {
      acme = {
        server = "https://acme-v02.api.letsencrypt.org/directory"
        email  = var.letsencrypt_email
        privateKeySecretRef = {
          name = "letsencrypt-dns01"
        }
        solvers = [
          {
            dns01 = {
              azureDNS = {
                clientID      = var.cert_manager_identity_client_id
                subscriptionID = var.subscription_id
                tenantID      = var.tenant_id
                resourceGroupName = var.dns_resource_group_name
                hostedZoneName   = var.dns_zone_name
                environment     = "AzurePublicCloud"
              }
            }
          }
        ]
      }
    }
  })

  depends_on = [helm_release.cert_manager]
}

# Example Certificate resource for automatic certificate provisioning
resource "kubectl_manifest" "example_certificate" {
  count = var.create_example_certificate ? 1 : 0
  
  yaml_body = yamlencode({
    apiVersion = "cert-manager.io/v1"
    kind       = "Certificate"
    metadata = {
      name      = "example-tls"
      namespace = "default"
    }
    spec = {
      secretName = "example-tls"
      issuerRef = {
        name = var.enable_letsencrypt_prod ? "letsencrypt-prod" : "letsencrypt-staging"
        kind = "ClusterIssuer"
      }
      dnsNames = var.certificate_dns_names
    }
  })

  depends_on = [
    kubectl_manifest.letsencrypt_staging,
    kubectl_manifest.letsencrypt_prod
  ]
}
