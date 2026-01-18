# Greenfield Azure Tenant Setup Guide

This guide is specifically for users with a **brand new Azure account and tenant** who want to deploy the Azure AKS GitOps platform from scratch.

## Perfect Fit Scenario

This project is **ideal** for greenfield Azure tenants because:
- No existing infrastructure conflicts
- Clean IP address space (10.0.0.0/16)
- No naming conflicts with existing resources
- Full control over security and compliance settings

## Prerequisites for New Azure Users

### Step 1: Azure Account Setup

If you don't have an Azure account yet:

1. **Create Azure Account**:
   - Visit [azure.microsoft.com](https://azure.microsoft.com/free/)
   - Sign up for free account (includes $200 credit)
   - Complete identity verification

2. **Understand Azure Hierarchy**:
   ```
   Azure Tenant (Your Organization)
   └── Subscription (Billing Boundary)
       └── Resource Groups (Logical Containers)
           └── Resources (VMs, Storage, etc.)
   ```

3. **Verify Subscription**:
   ```bash
   az login
   az account list --output table
   az account show
   ```

### Step 2: Check Required Permissions

Your account needs these permissions on the subscription:

- **Contributor** - Create and manage resources
- **User Access Administrator** - Assign roles to service principals
- **Key Vault Administrator** - Manage certificates and secrets

**Check your permissions**:
```bash
# Check if you can create resources
az group create --name permission-test-rg --location "East US"

# Check if you can create service principals
az ad sp create-for-rbac --name permission-test-sp --role Reader --scopes "/subscriptions/$(az account show --query id -o tsv)" --dry-run

# Clean up test resources
az group delete --name permission-test-rg --yes --no-wait
az ad sp delete --id $(az ad sp list --display-name permission-test-sp --query "[0].appId" -o tsv)
```

### Step 3: Cost Considerations

**Estimated Monthly Costs** (East US region):
- **Development Environment**: ~$200-400/month
  - AKS cluster (2 Standard_D2s_v3 nodes): ~$140
  - Application Gateway for Containers: ~$25
  - Storage and networking: ~$20-50
  - AI/ML node pool (if enabled): ~$200-400

- **Production Environment**: ~$500-1000/month
  - Larger node pools and redundancy
  - Premium storage and networking
  - Enhanced monitoring and security

**Cost Optimization Tips**:
- Start with dev environment only
- Use spot instances for non-critical workloads
- Enable auto-scaling to scale down during off-hours
- Monitor costs with Azure Cost Management

## Automated Setup Process

### Step 1: Clone and Prepare Repository

```bash
# Clone the repository
git clone git@github.com:cmcconnell1/aks-platform.git
cd aks-platform

# Make scripts executable
chmod +x scripts/*.sh scripts/*.py
```

### Step 2: Azure Authentication

```bash
# Login to Azure (will open browser)
az login

# List available subscriptions
az account list --output table

# Set your subscription (replace with your subscription ID)
az account set --subscription "your-subscription-id"

# Verify current subscription
az account show
```

### Step 3: Set Up Python Environment

Set up a virtual environment for the automation scripts:

```bash
# Automated setup (recommended)
./scripts/setup-python-env.sh

# Activate the virtual environment
source venv/bin/activate

# Verify the setup
python3 scripts/check-python-env.py
```

**Why use virtual environments?**
- Isolates project dependencies from system Python
- Ensures consistent package versions across environments
- Prevents conflicts with other Python projects
- Follows Python development best practices

### Step 4: Run Automated Azure Setup

Choose your preferred setup method:

```bash
# Option A: Bash script (recommended for Linux/macOS)
./scripts/setup-azure-credentials.sh

# Option B: Python script (cross-platform alternative)
./scripts/setup-azure-credentials.py
```

**What this creates**:
- Resource group for Terraform state storage
- Storage accounts for each environment (dev, staging, prod)
- Service principals with proper permissions
- Backend configuration files
- Environment-specific variable files

### Step 5: Configure GitHub Integration

```bash
# Login to GitHub CLI
gh auth login

# Configure GitHub secrets
./scripts/setup-github-secrets.sh
```

**What this configures**:
- Azure credentials as GitHub secrets
- Optional integrations (Infracost for cost estimation)
- Environment protection guidance

### Step 5: Customize Configuration

Edit the generated configuration for your needs:

```bash
# Edit development environment settings
vim terraform/environments/dev/terraform.tfvars
```

**Key settings for greenfield deployment**:
```hcl
# Project identification
project_name = "aks-platform"
location = "East US"  # Choose your preferred region

# Network configuration (default is fine for greenfield)
vnet_address_space = ["10.0.0.0/16"]
aks_subnet_address_prefix = "10.0.1.0/24"
agc_subnet_address_prefix = "10.0.2.0/24"

# Domain configuration (choose one option)

# Option A: No domain yet (fastest start)
create_demo_ssl_certificate = true
ssl_certificate_subject = "aks-platform.local"
enable_cert_manager = false

# Option B: Real domain (production-like)
# ssl_certificate_subject = "yourdomain.com"
# enable_cert_manager = true
# enable_azure_dns = true

# Cost optimization for development
enable_spot_instances = true  # Use cheaper spot instances
aks_min_node_count = 1       # Scale down when not in use
enable_ai_node_pool = false  # Disable expensive GPU nodes initially
```

## Deployment Options

### Option A: GitHub Actions (Recommended)

```bash
# Commit and push to trigger deployment
git add terraform/environments/*/backend.conf
git commit -m "feat: add Azure backend configuration"
git push origin main
```

Monitor deployment in GitHub Actions tab.

### Option B: Local Deployment

```bash
# Initialize Terraform
cd terraform
terraform init -backend-config=environments/dev/backend.conf

# Plan deployment
terraform plan -var-file=environments/dev/terraform.tfvars

# Apply (will take 15-20 minutes)
terraform apply -var-file=environments/dev/terraform.tfvars
```

## Post-Deployment Verification

### Check Infrastructure

```bash
# Get cluster credentials
az aks get-credentials \
  --resource-group $(terraform output -raw resource_group_name) \
  --name $(terraform output -raw aks_cluster_name)

# Verify cluster
kubectl get nodes
kubectl get pods --all-namespaces

# Get AGC frontend FQDN
terraform output agc_frontend_fqdn
```

### Access Platform Services

1. **ArgoCD**: `https://argocd.your-domain.com` (or use port-forward)
2. **Grafana**: `https://grafana.your-domain.com`
3. **JupyterHub**: `https://jupyter.your-domain.com`

**Get initial passwords**:
```bash
# ArgoCD admin password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d

# Grafana admin password
kubectl get secret --namespace monitoring prometheus-grafana \
  -o jsonpath="{.data.admin-password}" | base64 --decode
```

## Troubleshooting for New Users

### Common Permission Issues

**Error**: "Insufficient privileges to complete the operation"
```bash
# Check your role assignments
az role assignment list --assignee $(az account show --query user.name -o tsv) --output table

# Request additional permissions from subscription admin
```

**Error**: "Cannot create service principal"
```bash
# Check if you have permission to create service principals
az ad sp create-for-rbac --name test-sp --role Reader --dry-run
```

### Common Azure CLI Issues

**Error**: "Please run 'az login' to setup account"
```bash
# Clear cached credentials and re-login
az account clear
az login
```

**Error**: "Subscription not found"
```bash
# List available subscriptions
az account list --output table
# Set correct subscription
az account set --subscription "correct-subscription-id"
```

## Next Steps

1. **Explore the Platform**: Access ArgoCD, Grafana, and JupyterHub
2. **Deploy Applications**: Use ArgoCD for GitOps application deployment
3. **Configure Monitoring**: Set up alerts and dashboards in Grafana
4. **Security Hardening**: Review and implement additional security policies
5. **Production Planning**: Scale up for production workloads

## Tips for Success

- **Start Small**: Begin with dev environment only
- **Monitor Costs**: Set up billing alerts in Azure portal
- **Learn Gradually**: Explore one component at a time
- **Use Documentation**: Refer to other guides in the `docs/` directory
- **Join Community**: Engage with the project community for support

## Getting Help

- **Documentation**: Check other guides in `docs/` directory
- **GitHub Issues**: Create issues for bugs or questions
- **Azure Support**: Use Azure portal support for Azure-specific issues
- **Community**: Join relevant Slack/Discord communities

Your greenfield Azure tenant is now ready for modern cloud-native development!
