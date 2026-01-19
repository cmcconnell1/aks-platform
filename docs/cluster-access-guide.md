# Cluster Access Guide

This guide explains how to access AKS clusters in each environment, covering the differences between public and private cluster configurations.

## Overview

The platform uses different access patterns for non-production and production environments:

| Environment | API Server | Access Method | Use Case |
|-------------|------------|---------------|----------|
| **Dev** | Public | Direct kubectl | Developer access, rapid iteration |
| **Staging** | Public | Direct kubectl | Integration testing, pre-production validation |
| **Prod** | Private | VPN/Bastion/Private Link | Security-hardened production workloads |

## Architecture

```
                    +---------------------------+
                    |       Developer           |
                    +-------------+-------------+
                                  |
              +-------------------+-------------------+
              |                   |                   |
    +---------v---------+  +------v------+  +---------v---------+
    |   Dev Cluster     |  |   Staging   |  |   Prod Cluster    |
    |   (Public API)    |  |   (Public)  |  |   (Private API)   |
    +-------------------+  +-------------+  +-------------------+
              |                   |                   |
    +---------v---------+  +------v------+  +---------v---------+
    |  Public Internet  |  |   Public    |  |  Private VNet     |
    |  + IP Filtering   |  |  + IP Filter|  |  + VPN/Bastion    |
    +-------------------+  +-------------+  +-------------------+
```

## Non-Production Access (Dev/Staging)

### Configuration

Non-production environments use public API server endpoints with optional IP filtering:

```hcl
# Dev/Staging configuration
enable_private_cluster = false
authorized_ip_ranges   = ["your.public.ip.address/32"]
```

### Getting Credentials

```bash
# Development cluster
az aks get-credentials \
  --resource-group rg-aks-platform-dev \
  --name aks-aks-platform-dev \
  --overwrite-existing

# Staging cluster
az aks get-credentials \
  --resource-group rg-aks-platform-staging \
  --name aks-aks-platform-staging \
  --overwrite-existing
```

### Verify Access

```bash
# Check connection
kubectl cluster-info

# List nodes
kubectl get nodes

# Check your context
kubectl config current-context
```

### IP Filtering (Recommended)

Even with public API servers, restrict access to known IP ranges:

```hcl
# terraform/environments/dev/terraform.tfvars
authorized_ip_ranges = [
  "203.0.113.0/24",      # Office network
  "198.51.100.50/32",    # VPN exit IP
  "192.0.2.100/32"       # CI/CD runner IP
]
```

To find your current public IP:
```bash
curl -s ifconfig.me
```

### Context Management

Manage multiple cluster contexts:

```bash
# List all contexts
kubectl config get-contexts

# Switch to dev
kubectl config use-context aks-aks-platform-dev

# Switch to staging
kubectl config use-context aks-aks-platform-staging

# Rename context for easier use
kubectl config rename-context aks-aks-platform-dev dev
kubectl config rename-context aks-aks-platform-staging staging
```

## Production Access (Private Cluster)

### Configuration

Production uses a private API server endpoint:

```hcl
# Production configuration
enable_private_cluster = true
authorized_ip_ranges   = []  # Not used with private clusters
```

### Private Cluster Architecture

```
+------------------+     +------------------+     +------------------+
|   Developer      |     |  Azure VPN       |     |  AKS Private     |
|   Workstation    +---->+  Gateway         +---->+  API Server      |
+------------------+     +------------------+     +------------------+
                                                          |
                         +------------------+             |
                         |  Azure Bastion   +-------------+
                         +------------------+
                                  ^
                                  |
                         +--------+--------+
                         |   Jump Box VM   |
                         +-----------------+
```

### Access Methods

#### Option 1: Azure VPN Gateway (Recommended)

For regular production access, set up Azure VPN:

```bash
# 1. Download VPN client configuration
az network vnet-gateway vpn-client generate \
  --resource-group rg-aks-platform-prod \
  --name vpn-gateway-prod \
  --processor-architecture Amd64

# 2. Import VPN configuration to your VPN client

# 3. Connect to VPN

# 4. Get credentials (while connected to VPN)
az aks get-credentials \
  --resource-group rg-aks-platform-prod \
  --name aks-aks-platform-prod \
  --overwrite-existing

# 5. Verify access
kubectl get nodes
```

#### Option 2: Azure Bastion + Jump Box

For occasional access without VPN:

```bash
# 1. Connect to jump box via Bastion
az network bastion ssh \
  --name bastion-prod \
  --resource-group rg-aks-platform-prod \
  --target-resource-id /subscriptions/<sub>/resourceGroups/rg-aks-platform-prod/providers/Microsoft.Compute/virtualMachines/jumpbox-prod \
  --auth-type AAD

# 2. On the jump box, get credentials
az login
az aks get-credentials \
  --resource-group rg-aks-platform-prod \
  --name aks-aks-platform-prod

# 3. Run kubectl commands from jump box
kubectl get nodes
```

#### Option 3: Azure Cloud Shell

Access from Azure Portal's Cloud Shell (connected to your VNet):

```bash
# In Cloud Shell
az aks get-credentials \
  --resource-group rg-aks-platform-prod \
  --name aks-aks-platform-prod

kubectl get nodes
```

#### Option 4: AKS Run Command (Emergency Only)

For emergency access without network connectivity:

```bash
# Run commands directly via Azure API
az aks command invoke \
  --resource-group rg-aks-platform-prod \
  --name aks-aks-platform-prod \
  --command "kubectl get nodes"

# Run a script
az aks command invoke \
  --resource-group rg-aks-platform-prod \
  --name aks-aks-platform-prod \
  --command "kubectl get pods -A" \
  --file ./my-script.sh
```

**Note**: AKS Run Command should only be used for emergency troubleshooting, not regular operations.

### Private DNS Resolution

Private clusters require DNS resolution for the private API endpoint:

```bash
# Check the private FQDN
az aks show \
  --resource-group rg-aks-platform-prod \
  --name aks-aks-platform-prod \
  --query "privateFqdn" -o tsv

# Example output: aks-aks-platform-prod-abc123.privatelink.eastus.azmk8s.io
```

Ensure your VPN or jump box can resolve this FQDN via Azure Private DNS.

## CI/CD Pipeline Access

### GitHub Actions with OIDC

The platform uses OIDC federation for secure CI/CD access:

```yaml
# .github/workflows/deploy.yml
- name: Azure Login
  uses: azure/login@v1
  with:
    client-id: ${{ secrets.AZURE_CLIENT_ID }}
    tenant-id: ${{ secrets.AZURE_TENANT_ID }}
    subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}

- name: Get AKS Credentials
  run: |
    az aks get-credentials \
      --resource-group ${{ env.RESOURCE_GROUP }} \
      --name ${{ env.CLUSTER_NAME }}
```

### Self-Hosted Runners (Production)

For production private clusters, use self-hosted runners in the VNet:

```yaml
jobs:
  deploy-prod:
    runs-on: self-hosted  # Runner in production VNet
    steps:
      - name: Deploy to Production
        run: kubectl apply -f manifests/
```

## Kubernetes Authentication

### Azure AD Integration

All clusters use Azure AD for authentication:

```bash
# Interactive login (uses browser)
az aks get-credentials \
  --resource-group rg-aks-platform-dev \
  --name aks-aks-platform-dev

# First kubectl command will prompt for Azure AD login
kubectl get nodes
```

### Service Account Tokens (Automation)

For automated access, use Kubernetes service accounts:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: ci-deployer
  namespace: default
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: ci-deployer-binding
subjects:
  - kind: ServiceAccount
    name: ci-deployer
    namespace: default
roleRef:
  kind: ClusterRole
  name: cluster-admin  # Use least privilege in production
  apiGroup: rbac.authorization.k8s.io
```

## Accessing Platform Services

### Through Application Gateway for Containers

Platform services are exposed via AGC with Gateway API:

```bash
# Get the AGC frontend FQDN
kubectl get gateway -n default -o jsonpath='{.items[0].status.addresses[0].value}'

# Access services via DNS (after configuring DNS records)
# ArgoCD:    https://argocd.your-domain.com
# Grafana:   https://grafana.your-domain.com
# JupyterHub: https://jupyter.your-domain.com
# MLflow:    https://mlflow.your-domain.com
```

### Through Port Forwarding (Development)

For local development access:

```bash
# ArgoCD UI
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Grafana
kubectl port-forward svc/prometheus-grafana -n monitoring 3000:80

# JupyterHub
kubectl port-forward svc/proxy-public -n ai-tools 8000:80

# MLflow
kubectl port-forward svc/mlflow -n ai-tools 5000:5000
```

## Troubleshooting

### Cannot Connect to Cluster

```bash
# Check current context
kubectl config current-context

# Verify credentials are fresh
az aks get-credentials --resource-group <rg> --name <cluster> --overwrite-existing

# Test connectivity
kubectl cluster-info

# Check for network issues (private clusters)
nslookup <private-fqdn>
```

### Unauthorized Errors

```bash
# Re-authenticate with Azure
az login

# Clear cached tokens
rm -rf ~/.kube/cache

# Get fresh credentials
az aks get-credentials --resource-group <rg> --name <cluster> --overwrite-existing
```

### Private Cluster DNS Issues

```bash
# Verify VPN connection
ping 10.10.1.1  # Use an IP in the cluster VNet

# Check DNS resolution
nslookup aks-aks-platform-prod-abc123.privatelink.eastus.azmk8s.io

# Use Azure DNS server if needed
echo "nameserver 168.63.129.16" | sudo tee /etc/resolv.conf
```

### Context Conflicts

```bash
# List all contexts
kubectl config get-contexts

# Remove stale context
kubectl config delete-context <context-name>

# View kubeconfig
kubectl config view
```

## Security Best Practices

### Non-Production

1. **Use IP filtering** - Always set `authorized_ip_ranges` even for dev/staging
2. **Rotate credentials** - Refresh kubeconfig periodically
3. **Use namespaces** - Isolate workloads by team/project
4. **Audit access** - Enable Azure AD audit logs

### Production

1. **Never expose publicly** - Keep `enable_private_cluster = true`
2. **Use VPN for access** - Avoid bastion for regular operations
3. **Limit AKS Run Command** - Use only for emergencies
4. **Enable JIT access** - Use Azure PIM for elevated access
5. **Monitor access** - Set up alerts for unusual activity
6. **Network segmentation** - Use NSGs to limit traffic

## Related Documentation

- [Environment Configuration Guide](./environment-configuration-guide.md)
- [Security Guide](./security.md)
- [Azure Workload Identity Guide](./azure-workload-identity.md)
- [Deployment Guide](./deployment-guide.md)
- [Troubleshooting Guide](./troubleshooting.md)
