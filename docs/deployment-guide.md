# Azure AKS Platform Deployment Guide

This guide walks you through deploying the complete Azure AKS platform with Application Gateway Ingress Controller (AGIC), ArgoCD, and AI/ML tools.

## Prerequisites

### Required Tools
- [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli) >= 2.40.0
- [Terraform](https://www.terraform.io/downloads.html) >= 1.0
- [kubectl](https://kubernetes.io/docs/tasks/tools/) >= 1.25
- [Helm](https://helm.sh/docs/intro/install/) >= 3.10
- [GitHub CLI](https://cli.github.com/) >= 2.0 (for automated setup)
- [jq](https://stedolan.github.io/jq/) (for JSON processing)
- **Python 3.7+** with pip (for automation scripts)
- **Bash shell** (Linux/macOS native, Windows via WSL2 or Git Bash)

### Python Environment Setup
Set up a virtual environment for better dependency management:

```bash
# Automated setup (recommended)
./scripts/setup-python-env.sh

# Check environment status
python3 scripts/check-python-env.py

# Manual setup (alternative)
python3 -m venv venv
source venv/bin/activate
pip install -r scripts/requirements.txt
```

### Azure Permissions
Your Azure account needs the following permissions:
- Contributor role on the subscription
- User Access Administrator role (for RBAC assignments)
- Key Vault Administrator role (for certificate management)
- Ability to create service principals

### GitHub Repository
- GitHub repository with Actions enabled
- Admin access to configure secrets and environments

### Platform Requirements
- **Linux/macOS**: Native bash support
- **Windows**: Use WSL2 (recommended) or Git Bash for script execution

## Step 1: Automated Azure Setup

The project includes automated scripts to set up all required Azure resources and credentials.

### Option A: Automated Setup (Recommended)

```bash
# Make scripts executable
chmod +x scripts/*.sh scripts/*.py

# Login to Azure
az login

# Set your subscription
az account set --subscription "your-subscription-id"

# Run the automated setup (choose one)
./scripts/setup-azure-credentials.sh    # Bash version
# OR
./scripts/setup-azure-credentials.py    # Python version
```

This script will:
- Create resource groups for Terraform state
- Create storage accounts for each environment
- Create service principals with proper permissions
- Generate backend configuration files
- Create environment-specific tfvars files

### Option B: Manual Setup

If you prefer manual setup, follow the original process:

```bash
# Login to Azure
az login

# Set your subscription
az account set --subscription "your-subscription-id"

# Verify your account
az account show
```

Create a storage account for Terraform state:

```bash
# Create resource group for Terraform state
az group create --name terraform-state-rg --location "East US"

# Create storage account
az storage account create \
  --name tfstateaksplatformdev \
  --resource-group terraform-state-rg \
  --location "East US" \
  --sku Standard_LRS \
  --encryption-services blob

# Create container
az storage container create \
  --name tfstate \
  --account-name tfstateaksplatformdev
```

## Step 2: GitHub Repository Setup

Set up GitHub repository secrets for CI/CD automation:

```bash
# Login to GitHub CLI
gh auth login

# Run the GitHub secrets setup script
./scripts/setup-github-secrets.sh
```

This script will:
- Configure Azure service principal credentials as GitHub secrets
- Set up optional secrets (Infracost, Slack notifications)
- Guide you through environment protection setup

## Step 3: Configure Environment

If you used the automated setup, configuration files are already generated. Otherwise:

1. **Copy configuration files**:
   ```bash
   cd terraform/environments/dev
   cp terraform.tfvars.example terraform.tfvars
   cp backend.conf.example backend.conf
   ```

2. **Update terraform.tfvars** with your specific values:
   ```hcl
   # Update these values
   ssl_certificate_subject = "your-domain.com"
   ssl_certificate_dns_names = ["your-domain.com", "*.your-domain.com"]
   authorized_ip_ranges = ["your.public.ip.address/32"]
   ```

3. **Load environment variables** (if using manual deployment):
   ```bash
   source .env
   ```

## Step 4: Deploy Infrastructure

### Option A: Using GitHub Actions (Recommended)

1. **Create a pull request** with your configuration changes:
   ```bash
   git checkout -b feature/initial-deployment
   git add .
   git commit -m "Initial infrastructure configuration"
   git push origin feature/initial-deployment
   ```

2. **Open pull request** - This will trigger:
   - Terraform plan for all environments
   - Security scanning with Checkov and TFSec
   - Cost estimation with Infracost
   - Automated PR comments with results

3. **Review and merge** - After approval, merge to main branch to trigger deployment

### Option B: Manual Deployment

1. **Initialize Terraform**:
   ```bash
   cd terraform
   terraform init -backend-config=environments/dev/backend.conf
   ```

2. **Plan deployment**:
   ```bash
   terraform plan -var-file=environments/dev/terraform.tfvars
   ```

3. **Apply configuration**:
   ```bash
   terraform apply -var-file=environments/dev/terraform.tfvars
   ```

### What Gets Created

The deployment will create:
- Resource Group
- Virtual Network with subnets and security groups
- AKS cluster with system and user node pools
- AI/ML node pool with GPU support
- Application Gateway with AGIC and WAF
- Azure Container Registry with private endpoints
- Key Vault with SSL certificates and secrets
- Log Analytics workspace and Application Insights
- Monitoring stack (Prometheus, Grafana, Loki)
- GitOps platform (ArgoCD)
- AI/ML tools (JupyterHub, MLflow)

## Step 5: Configure kubectl

```bash
# Get AKS credentials
az aks get-credentials \
  --resource-group $(terraform output -raw resource_group_name) \
  --name $(terraform output -raw aks_cluster_name)

# Verify connection
kubectl get nodes
```

## Step 6: Verify Deployments

### Check AKS Cluster
```bash
# Check nodes
kubectl get nodes -o wide

# Check system pods
kubectl get pods -n kube-system

# Check AGIC
kubectl get pods -n kube-system | grep ingress
```

### Check ArgoCD
```bash
# Check ArgoCD pods
kubectl get pods -n argocd

# Get ArgoCD admin password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d

# Port forward to access ArgoCD UI
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

### Check AI Tools
```bash
# Check JupyterHub
kubectl get pods -n ai-tools | grep jupyter

# Check MLflow
kubectl get pods -n ai-tools | grep mlflow

# Check GPU operator (if enabled)
kubectl get pods -n gpu-operator
```

### Check Monitoring
```bash
# Check Prometheus and Grafana
kubectl get pods -n monitoring

# Get Grafana admin password
kubectl get secret --namespace monitoring prometheus-grafana \
  -o jsonpath="{.data.admin-password}" | base64 --decode
```

## Step 7: Access Applications

### Through Application Gateway (Recommended)

1. **Get Application Gateway IP**:
   ```bash
   terraform output application_gateway_public_ip
   ```

2. **Update DNS or hosts file**:
   ```
   <APP_GATEWAY_IP> argocd.your-domain.com
   <APP_GATEWAY_IP> grafana.your-domain.com
   <APP_GATEWAY_IP> jupyter.your-domain.com
   <APP_GATEWAY_IP> mlflow.your-domain.com
   ```

3. **Access applications**:
   - ArgoCD: https://argocd.your-domain.com
   - Grafana: https://grafana.your-domain.com
   - JupyterHub: https://jupyter.your-domain.com
   - MLflow: https://mlflow.your-domain.com

### Through Port Forwarding (Development)

```bash
# ArgoCD
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Grafana
kubectl port-forward svc/prometheus-grafana -n monitoring 3000:80

# JupyterHub
kubectl port-forward svc/proxy-public -n ai-tools 8000:80

# MLflow
kubectl port-forward svc/mlflow -n ai-tools 5000:5000
```

## Step 8: Container Registry Access

```bash
# Login to ACR
az acr login --name $(terraform output -raw container_registry_name)

# Test push/pull
docker pull hello-world
docker tag hello-world $(terraform output -raw container_registry_login_server)/hello-world:latest
docker push $(terraform output -raw container_registry_login_server)/hello-world:latest
```

## Troubleshooting

### Common Issues

1. **AGIC not working**:
   ```bash
   # Check AGIC logs
   kubectl logs -n kube-system -l app=ingress-appgw
   
   # Check Application Gateway backend health
   az network application-gateway show-backend-health \
     --name <app-gateway-name> \
     --resource-group <resource-group>
   ```

2. **GPU nodes not ready**:
   ```bash
   # Check GPU operator
   kubectl get pods -n gpu-operator
   
   # Check node labels
   kubectl get nodes --show-labels | grep gpu
   ```

3. **ArgoCD not accessible**:
   ```bash
   # Check ingress
   kubectl get ingress -n argocd
   
   # Check service
   kubectl get svc -n argocd
   ```

### Useful Commands

```bash
# Get all ingresses
kubectl get ingress --all-namespaces

# Check Application Gateway configuration
az network application-gateway list --output table

# Monitor resource usage
kubectl top nodes
kubectl top pods --all-namespaces
```

## Cleanup

To destroy all resources:

```bash
terraform destroy -var-file=environments/dev/terraform.tfvars
```

**Warning**: This will delete all resources including data. Make sure to backup any important data first.

## Next Steps

1. Configure ArgoCD applications for GitOps
2. Set up monitoring alerts
3. Configure backup strategies
4. Implement security policies
5. Set up CI/CD pipelines
