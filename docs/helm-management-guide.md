# Helm Chart Management Guide

This guide explains how Helm charts are managed in the Azure AKS GitOps project, covering both infrastructure and application chart management strategies.

## Architecture Overview

The project uses a **two-tier Helm management approach**:

1. **Infrastructure Charts** - Managed by Terraform for platform services
2. **Application Charts** - Managed by ArgoCD for GitOps workflows

## Tier 1: Infrastructure Charts (Terraform-Managed)

### Core Platform Services

These charts are deployed directly by Terraform during infrastructure provisioning:

#### **ArgoCD** - GitOps Platform
```hcl
resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = "5.51.6"
  namespace  = "argocd"
}
```

#### **Monitoring Stack** - Observability Platform
```hcl
resource "helm_release" "prometheus" {
  name       = "prometheus"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  version    = "55.5.0"
  namespace  = "monitoring"
}
```

#### **AI/ML Tools** - Data Science Platform
```hcl
# JupyterHub
resource "helm_release" "jupyterhub" {
  name       = "jupyterhub"
  repository = "https://jupyterhub.github.io/helm-chart/"
  chart      = "jupyterhub"
  version    = "3.1.0"
  namespace  = "ai-tools"
}

# MLflow
resource "helm_release" "mlflow" {
  name       = "mlflow"
  repository = "https://community-charts.github.io/helm-charts"
  chart      = "mlflow"
  version    = "0.7.19"
  namespace  = "ai-tools"
}

# NVIDIA GPU Operator
resource "helm_release" "gpu_operator" {
  name       = "gpu-operator"
  repository = "https://nvidia.github.io/gpu-operator"
  chart      = "gpu-operator"
  version    = "v23.9.1"
  namespace  = "gpu-operator"
}
```

#### **Certificate Management**
```hcl
resource "helm_release" "cert_manager" {
  name       = "cert-manager"
  repository = "https://charts.jetstack.io"
  chart      = "cert-manager"
  version    = "v1.13.2"
  namespace  = "cert-manager"
}
```

### Chart Repositories Used

| Repository | Purpose | Charts |
|------------|---------|--------|
| `https://argoproj.github.io/argo-helm` | GitOps | ArgoCD |
| `https://prometheus-community.github.io/helm-charts` | Monitoring | Prometheus, Grafana, Loki |
| `https://jupyterhub.github.io/helm-chart/` | AI/ML | JupyterHub |
| `https://community-charts.github.io/helm-charts` | AI/ML | MLflow |
| `https://nvidia.github.io/gpu-operator` | GPU | NVIDIA GPU Operator |
| `https://charts.jetstack.io` | Security | cert-manager |
| `https://jaegertracing.github.io/helm-charts` | Observability | Jaeger |

## Tier 2: Application Charts (ArgoCD-Managed)

### App-of-Apps Pattern

ArgoCD manages application deployments using the **App-of-Apps pattern**:

```yaml
# Initial ArgoCD Application for app-of-apps pattern
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: app-of-apps
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/your-org/aks-apps
    targetRevision: main
    path: apps
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

### Application Repository Structure

```
aks-apps/
├── apps/
│   ├── app-of-apps.yaml
│   ├── web-applications/
│   │   ├── frontend-app.yaml
│   │   └── backend-api.yaml
│   ├── microservices/
│   │   ├── user-service.yaml
│   │   └── order-service.yaml
│   └── data-pipelines/
│       ├── etl-pipeline.yaml
│       └── ml-training.yaml
├── charts/
│   ├── custom-app/
│   │   ├── Chart.yaml
│   │   ├── values.yaml
│   │   └── templates/
│   └── shared-library/
└── environments/
    ├── dev/
    ├── staging/
    └── prod/
```

## Chart Version Management

### Infrastructure Charts (Terraform)

**Version Pinning Strategy**:
- All chart versions are explicitly pinned in Terraform
- Updates require code changes and CI/CD approval
- Versions tested in dev before production

**Update Process**:
1. Update chart version in Terraform code
2. Test in development environment
3. Create pull request with changes
4. CI/CD validates and plans changes
5. Merge triggers deployment

### Application Charts (ArgoCD)

**GitOps Version Management**:
- Chart versions specified in ArgoCD Application manifests
- Automatic sync policies for continuous deployment
- Environment-specific value overrides

**Update Process**:
1. Update chart version in Git repository
2. ArgoCD detects changes automatically
3. Sync policy determines deployment behavior
4. Health checks validate deployment

## Configuration Management

### Terraform Values

Infrastructure charts use Terraform variables for configuration:

```hcl
# JupyterHub configuration
values = [
  yamlencode({
    hub = {
      config = {
        JupyterHub = {
          admin_access = true
          authenticator_class = "dummy"
        }
        DummyAuthenticator = {
          password = var.jupyter_admin_password
        }
      }
    }
    singleuser = {
      image = {
        name = var.jupyter_notebook_image
        tag  = var.jupyter_notebook_tag
      }
      cpu = {
        limit     = var.jupyter_user_cpu_limit
        guarantee = var.jupyter_user_cpu_guarantee
      }
      memory = {
        limit     = var.jupyter_user_memory_limit
        guarantee = var.jupyter_user_memory_guarantee
      }
    }
  })
]
```

### ArgoCD Values

Application charts use Git-stored values files:

```yaml
# values/jupyterhub/dev.yaml
hub:
  config:
    JupyterHub:
      admin_access: true
    DummyAuthenticator:
      password: "dev-password"

singleuser:
  cpu:
    limit: "1"
    guarantee: "0.1"
  memory:
    limit: "2G"
    guarantee: "512M"
```

## Security and Best Practices

### Chart Security

1. **Repository Verification**:
   - Only use trusted Helm repositories
   - Verify chart signatures when available
   - Regular security scanning of chart dependencies

2. **Version Management**:
   - Pin specific chart versions (no `latest`)
   - Test updates in non-production environments
   - Maintain changelog for chart updates

3. **Secret Management**:
   - Use Azure Key Vault for sensitive values
   - Kubernetes secrets for chart-specific secrets
   - Never commit secrets to Git repositories

### Resource Management

1. **Resource Limits**:
   - All charts have explicit resource limits
   - CPU and memory requests/limits defined
   - Storage quotas for persistent volumes

2. **Security Contexts**:
   - Non-root users where possible
   - Read-only root filesystems
   - Security policies enforced

## Monitoring and Observability

### Chart Health Monitoring

1. **ArgoCD Health Checks**:
   - Application sync status
   - Resource health validation
   - Automatic remediation policies

2. **Prometheus Metrics**:
   - Chart deployment metrics
   - Resource utilization monitoring
   - Alert rules for failures

3. **Logging**:
   - Centralized logging with Loki
   - Chart deployment logs
   - Application-specific log aggregation

## Troubleshooting

### Common Issues

1. **Chart Installation Failures**:
   ```bash
   # Check Helm release status
   helm list -A
   helm status <release-name> -n <namespace>
   
   # View release history
   helm history <release-name> -n <namespace>
   ```

2. **ArgoCD Sync Issues**:
   ```bash
   # Check application status
   argocd app get <app-name>
   argocd app sync <app-name>
   
   # View sync logs
   argocd app logs <app-name>
   ```

3. **Resource Conflicts**:
   ```bash
   # Check resource ownership
   kubectl get <resource> -o yaml | grep ownerReferences
   
   # Force delete stuck resources
   kubectl patch <resource> -p '{"metadata":{"finalizers":[]}}' --type=merge
   ```

### Rollback Procedures

1. **Terraform-Managed Charts**:
   ```bash
   # Rollback via Terraform
   terraform plan -target=module.ai_tools.helm_release.jupyterhub
   terraform apply -target=module.ai_tools.helm_release.jupyterhub
   ```

2. **ArgoCD-Managed Charts**:
   ```bash
   # Rollback via ArgoCD
   argocd app rollback <app-name> <revision>
   
   # Or via Git revert
   git revert <commit-hash>
   git push origin main
   ```

## Best Practices Summary

1. **Infrastructure Charts**: Use Terraform for platform services that require cluster-admin privileges
2. **Application Charts**: Use ArgoCD for user applications and workloads
3. **Version Pinning**: Always pin chart versions for reproducible deployments
4. **Environment Separation**: Use different values files for dev/staging/prod
5. **Security First**: Implement proper RBAC, resource limits, and secret management
6. **Monitoring**: Monitor both infrastructure and application chart health
7. **Documentation**: Maintain clear documentation for chart configurations and update procedures

This hybrid approach provides the best of both worlds: reliable infrastructure provisioning with Terraform and flexible application management with GitOps.
