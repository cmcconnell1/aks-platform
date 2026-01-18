# Azure Workload Identity Guide

This guide explains how Azure Workload Identity is implemented in the AKS platform, enabling secure, secretless authentication from Kubernetes pods to Azure services.

## Table of Contents

1. [Overview](#overview)
2. [Why Workload Identity](#why-workload-identity)
3. [Architecture](#architecture)
4. [Implementation Details](#implementation-details)
5. [Component Configuration](#component-configuration)
6. [Adding New Workload Identities](#adding-new-workload-identities)
7. [Troubleshooting](#troubleshooting)
8. [Best Practices](#best-practices)

## Overview

Azure Workload Identity is a feature that allows Kubernetes workloads to access Azure resources securely without managing secrets. It uses OpenID Connect (OIDC) federation to establish trust between Kubernetes ServiceAccounts and Azure AD managed identities.

### Key Concepts

| Term | Description |
|------|-------------|
| **OIDC Issuer** | AKS cluster endpoint that issues tokens for ServiceAccounts |
| **Federated Credential** | Azure AD configuration that trusts tokens from the OIDC issuer |
| **Managed Identity** | Azure AD identity used by pods to access Azure resources |
| **ServiceAccount** | Kubernetes identity associated with pods |

## Why Workload Identity

### Comparison with Previous Approaches

| Feature | AAD Pod Identity (Deprecated) | Workload Identity (Current) |
|---------|------------------------------|----------------------------|
| Secret Management | Required NMI daemon | No secrets needed |
| Performance | NMI added latency | Direct token exchange |
| Complexity | Required node taints | Standard Kubernetes patterns |
| Security | Broader attack surface | Minimal, scoped tokens |
| Support | Deprecated 2022 | Actively maintained |
| Azure Arc | Limited support | Full support |

### Benefits

1. **No Secrets to Manage**: Pods authenticate using short-lived tokens, not stored credentials
2. **Reduced Attack Surface**: No secrets that can be leaked or stolen
3. **Simplified Operations**: No additional components to manage
4. **Standard Kubernetes Patterns**: Uses native ServiceAccount mechanisms
5. **Fine-grained Access**: Each workload can have its own identity and permissions

## Architecture

```
+------------------+     +-------------------+     +------------------+
|   Kubernetes     |     |    Azure AD       |     |  Azure Services  |
|   Pod            |     |                   |     |                  |
+------------------+     +-------------------+     +------------------+
        |                        |                        |
        | 1. Request token       |                        |
        |   (ServiceAccount)     |                        |
        v                        |                        |
+------------------+             |                        |
|  OIDC Issuer     |             |                        |
|  (AKS Cluster)   |             |                        |
+------------------+             |                        |
        |                        |                        |
        | 2. Issue JWT token     |                        |
        |   with SA claims       |                        |
        v                        |                        |
+------------------+             |                        |
|  Pod receives    |             |                        |
|  projected token |             |                        |
+------------------+             |                        |
        |                        |                        |
        | 3. Exchange token      |                        |
        |   for Azure token      |                        |
        +----------------------->|                        |
                                 |                        |
                                 | 4. Validate:           |
                                 |  - Issuer (OIDC URL)   |
                                 |  - Subject (SA claim)  |
                                 |  - Audience            |
                                 |                        |
                                 | 5. Issue Azure token   |
                                 +----------------------->|
                                                          |
                                                 6. Access resources
```

## Implementation Details

### AKS Cluster Configuration

The AKS cluster is configured with OIDC issuer and workload identity enabled:

```hcl
# terraform/modules/aks/main.tf
resource "azurerm_kubernetes_cluster" "main" {
  # ...

  # Azure Workload Identity (2026 best practice)
  oidc_issuer_enabled       = true
  workload_identity_enabled = true
}
```

### Managed Identities

Managed identities are created for each component in the security module:

```hcl
# terraform/modules/security/main.tf

# Monitoring identity (Prometheus, Grafana)
resource "azurerm_user_assigned_identity" "monitoring" {
  name                = "${var.project_name}-${var.environment}-monitoring-identity"
  resource_group_name = var.resource_group_name
  location            = var.location
}

# GitOps identity (ArgoCD)
resource "azurerm_user_assigned_identity" "gitops" {
  name                = "${var.project_name}-${var.environment}-gitops-identity"
  resource_group_name = var.resource_group_name
  location            = var.location
}

# AI Tools identity (JupyterHub, MLflow)
resource "azurerm_user_assigned_identity" "ai_tools" {
  name                = "${var.project_name}-${var.environment}-ai-tools-identity"
  resource_group_name = var.resource_group_name
  location            = var.location
}
```

### Federated Credentials

Federated credentials establish trust between Kubernetes ServiceAccounts and Azure managed identities:

```hcl
# terraform/workload_identity.tf

resource "azurerm_federated_identity_credential" "grafana" {
  name                = "${var.project_name}-${var.environment}-grafana"
  resource_group_name = azurerm_resource_group.main.name
  parent_id           = module.security.monitoring_identity_id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = module.aks.oidc_issuer_url
  subject             = "system:serviceaccount:monitoring:prometheus-grafana"
}
```

## Component Configuration

### Monitoring Stack (Prometheus/Grafana)

```hcl
# ServiceAccount annotation
serviceAccount = {
  annotations = {
    "azure.workload.identity/client-id" = var.workload_identity_client_id
  }
}

# Pod label
podLabels = {
  "azure.workload.identity/use" = "true"
}
```

**Federated Credentials:**
- `prometheus-grafana` ServiceAccount in `monitoring` namespace
- `prometheus-kube-prometheus-prometheus` ServiceAccount in `monitoring` namespace

### ArgoCD

```hcl
# Server ServiceAccount
server = {
  serviceAccount = {
    annotations = {
      "azure.workload.identity/client-id" = var.workload_identity_client_id
    }
  }
  podLabels = {
    "azure.workload.identity/use" = "true"
  }
}
```

**Federated Credentials:**
- `argocd-server` ServiceAccount in `argocd` namespace
- `argocd-application-controller` ServiceAccount in `argocd` namespace
- `argocd-repo-server` ServiceAccount in `argocd` namespace

### AI Tools (JupyterHub/MLflow)

```hcl
# Hub ServiceAccount
hub = {
  serviceAccount = {
    annotations = {
      "azure.workload.identity/client-id" = var.workload_identity_client_id
    }
  }
  extraLabels = {
    "azure.workload.identity/use" = "true"
  }
}
```

**Federated Credentials:**
- `hub` ServiceAccount in `ai-tools` namespace (JupyterHub)
- `mlflow` ServiceAccount in `ai-tools` namespace

### cert-manager

```hcl
# Already configured in cert_manager module
serviceAccount = {
  annotations = {
    "azure.workload.identity/client-id" = var.cert_manager_identity_client_id
  }
}
podLabels = {
  "azure.workload.identity/use" = "true"
}
```

### ALB Controller (for AGC)

The ALB Controller uses workload identity for managing Application Gateway for Containers:

```hcl
# ALB Controller ServiceAccount configuration
albController = {
  podIdentity = {
    clientID = azurerm_user_assigned_identity.alb_controller.client_id
  }
}
```

**Federated Credential:**
- `alb-controller-sa` ServiceAccount in `azure-alb-system` namespace

## Adding New Workload Identities

### Step 1: Create Managed Identity

Add to `terraform/modules/security/main.tf`:

```hcl
resource "azurerm_user_assigned_identity" "my_component" {
  count = var.enable_my_component ? 1 : 0

  name                = "${var.project_name}-${var.environment}-my-component-identity"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
}
```

### Step 2: Create Federated Credential

Add to `terraform/workload_identity.tf`:

```hcl
resource "azurerm_federated_identity_credential" "my_component" {
  count = var.enable_my_component ? 1 : 0

  name                = "${var.project_name}-${var.environment}-my-component"
  resource_group_name = azurerm_resource_group.main.name
  parent_id           = module.security.my_component_identity_id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = module.aks.oidc_issuer_url
  subject             = "system:serviceaccount:my-namespace:my-serviceaccount"

  depends_on = [module.aks, module.security]
}
```

### Step 3: Add Output

Add to `terraform/modules/security/outputs.tf`:

```hcl
output "my_component_identity_client_id" {
  description = "Client ID of the my-component managed identity"
  value       = var.enable_my_component ? azurerm_user_assigned_identity.my_component[0].client_id : null
}
```

### Step 4: Configure Component

Add to your Helm values or Kubernetes manifest:

```yaml
# ServiceAccount
apiVersion: v1
kind: ServiceAccount
metadata:
  name: my-serviceaccount
  namespace: my-namespace
  annotations:
    azure.workload.identity/client-id: <CLIENT_ID>
---
# Pod
apiVersion: v1
kind: Pod
metadata:
  name: my-pod
  namespace: my-namespace
  labels:
    azure.workload.identity/use: "true"
spec:
  serviceAccountName: my-serviceaccount
```

### Step 5: Assign Azure Permissions

```hcl
resource "azurerm_role_assignment" "my_component_storage" {
  scope                = azurerm_storage_account.main.id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = azurerm_user_assigned_identity.my_component[0].principal_id
}
```

## Troubleshooting

### Common Issues

#### 1. Pod Cannot Get Token

**Symptoms:**
- Error: `failed to get token: no token found`
- Pod stuck in authentication loop

**Solutions:**
1. Verify ServiceAccount has correct annotation:
   ```bash
   kubectl get sa -n <namespace> <serviceaccount> -o yaml
   ```
2. Verify pod has correct label:
   ```bash
   kubectl get pod -n <namespace> <pod> -o yaml | grep -A5 labels
   ```
3. Check federated credential exists:
   ```bash
   az ad app federated-credential list --id <app-id>
   ```

#### 2. Token Exchange Fails

**Symptoms:**
- Error: `AADSTS70021: No matching federated identity record found`

**Solutions:**
1. Verify the subject claim matches:
   ```bash
   # Get actual subject from pod
   kubectl exec -n <namespace> <pod> -- cat /var/run/secrets/azure/tokens/azure-identity-token | jwt decode -

   # Compare with federated credential
   az ad app federated-credential show --id <app-id> --federated-credential-id <cred-name>
   ```
2. Ensure issuer URL matches exactly (check trailing slashes)

#### 3. Permission Denied

**Symptoms:**
- Error: `AuthorizationFailed` or `ForbiddenByRbac`

**Solutions:**
1. Verify role assignment exists:
   ```bash
   az role assignment list --assignee <managed-identity-object-id>
   ```
2. Check correct scope for role assignment
3. Wait for role assignment propagation (can take a few minutes)

### Debugging Commands

```bash
# Check OIDC issuer URL
az aks show -n <cluster-name> -g <resource-group> --query oidcIssuerProfile.issuerUrl -o tsv

# List all federated credentials
az ad app federated-credential list --id <app-id> -o table

# Check ServiceAccount annotations
kubectl get sa -A -o custom-columns='NAMESPACE:.metadata.namespace,NAME:.metadata.name,CLIENT_ID:.metadata.annotations.azure\.workload\.identity/client-id'

# Check pods with workload identity enabled
kubectl get pods -A -l azure.workload.identity/use=true -o wide

# View projected token in pod
kubectl exec -n <namespace> <pod> -- cat /var/run/secrets/azure/tokens/azure-identity-token
```

## Best Practices

### Security

1. **Principle of Least Privilege**: Assign only necessary permissions to each managed identity
2. **Separate Identities**: Use different identities for different components
3. **Audit Regularly**: Review role assignments and federated credentials
4. **Monitor Token Usage**: Enable Azure AD sign-in logs for managed identities

### Operations

1. **Use Terraform**: Manage all workload identity resources through Terraform
2. **Document Subjects**: Keep a mapping of ServiceAccounts to managed identities
3. **Test Before Production**: Verify workload identity works in dev/staging first
4. **Monitor Failures**: Set up alerts for authentication failures

### Development

1. **Local Testing**: Use Azure CLI authentication for local development
2. **Environment Variables**: Use `AZURE_CLIENT_ID`, `AZURE_TENANT_ID` for SDK configuration
3. **SDK Support**: Ensure your Azure SDK version supports workload identity

## Related Documentation

- [Azure Workload Identity Documentation](https://learn.microsoft.com/en-us/azure/aks/workload-identity-overview)
- [Security Guide](./security.md)
- [Deployment Guide](./deployment-guide.md)
- [Azure GitHub OIDC Setup](./azure-github-oidc-setup.md)
