# Greenfield Azure Tenant Deployment Validation

This document provides a comprehensive validation checklist and order of operations for deploying the Azure AKS GitOps platform to a brand new Azure tenant with no existing infrastructure.

## Deployment Readiness Checklist

### Prerequisites Validation

#### Azure Account Setup
- [ ] Azure account created with valid subscription
- [ ] Azure CLI installed and authenticated (`az login`)
- [ ] Subscription has sufficient quota for AKS clusters
- [ ] Account has required permissions:
  - [ ] Contributor role on subscription
  - [ ] User Access Administrator role
  - [ ] Key Vault Administrator role
  - [ ] Ability to create service principals

#### Local Development Environment
- [ ] Azure CLI >= 2.40.0 (`az --version`)
- [ ] Terraform >= 1.0 (`terraform --version`)
- [ ] kubectl >= 1.25 (`kubectl version --client`)
- [ ] Helm >= 3.10 (`helm version`)
- [ ] GitHub CLI >= 2.0 (`gh --version`)
- [ ] jq installed (`jq --version`)
- [ ] Bash shell available (Linux/macOS native, Windows WSL2)

#### GitHub Repository Setup
- [ ] GitHub repository created and cloned
- [ ] GitHub Actions enabled
- [ ] Admin access to repository for secrets configuration
- [ ] Repository contains all project files

## Deployment Methods

### Method 1: Automated Pipeline Deployment (Recommended)

Complete deployment using GitHub Actions with minimal manual intervention.

#### Step 1: Initial Azure Setup
```bash
# Clone repository
git clone git@github.com:cmcconnell1/aks-platform.git
cd aks-platform

# Make scripts executable
chmod +x scripts/*.sh scripts/*.py

# Login to Azure
az login

# Set subscription
az account set --subscription "your-subscription-id"

# Run automated Azure setup
./scripts/setup-azure-credentials.sh
```

#### Step 2: Configure GitHub Secrets
```bash
# Automated GitHub secrets setup
./scripts/setup-github-secrets.sh
```

#### Step 3: Configure Deployment Variables
Create `terraform/environments/dev/terraform.tfvars`:
```hcl
# Basic Configuration
project_name = "your-project-name"
location = "East US"
environment = "dev"

# Certificate Management (Choose One)
# Option A: Let's Encrypt (Recommended for production domains)
enable_cert_manager = true
letsencrypt_email = "admin@yourdomain.com"
enable_letsencrypt_staging = true
ssl_certificate_subject = "yourdomain.com"
ssl_certificate_dns_names = ["yourdomain.com", "*.yourdomain.com"]

# Option B: Self-signed certificates (for testing)
create_demo_ssl_certificate = true

# AI/ML Features
enable_ai_tools = true
enable_gpu_node_pool = false  # Set to true if you need GPU workloads

# Monitoring
enable_monitoring = true
enable_grafana = true
```

#### Step 4: Deploy via GitHub Actions
1. Commit and push configuration:
   ```bash
   git add terraform/environments/*/backend.conf
   git commit -m "feat: add Azure backend configuration"
   git push origin main
   ```

2. Monitor deployment in GitHub Actions:
   - Go to repository → Actions tab
   - Watch "Terraform Deploy" workflow
   - Deployment takes 15-30 minutes

#### Step 5: Verify Deployment
```bash
# Get AKS credentials
az aks get-credentials --resource-group rg-your-project-dev --name aks-your-project-dev

# Verify cluster access
kubectl get nodes

# Check platform services
kubectl get pods -A

# Access ArgoCD UI
kubectl port-forward svc/argocd-server -n argocd 8080:443
# Open https://localhost:8080
```

### Method 2: Manual Step-by-Step Deployment

For users who prefer manual control or need to understand each step.

#### Phase 1: Infrastructure Foundation
```bash
# 1. Azure credentials setup
./scripts/setup-azure-credentials.sh

# 2. Initialize Terraform
cd terraform/environments/dev
terraform init

# 3. Plan infrastructure
terraform plan -var-file="terraform.tfvars"

# 4. Deploy infrastructure
terraform apply -var-file="terraform.tfvars"
```

#### Phase 2: Platform Services
```bash
# 1. Get AKS credentials
az aks get-credentials --resource-group rg-your-project-dev --name aks-your-project-dev

# 2. Deploy ArgoCD
kubectl apply -k platform/argocd/

# 3. Deploy monitoring stack
kubectl apply -k platform/monitoring/

# 4. Deploy AI/ML tools (if enabled)
kubectl apply -k platform/ai-tools/
```

#### Phase 3: Application Deployment
```bash
# 1. Configure ArgoCD applications
kubectl apply -f applications/

# 2. Verify deployments
kubectl get applications -n argocd
```

## Certificate Management Decision Guide

### Option 1: Let's Encrypt (Recommended for Production)

**Best for:**
- Production environments with real domains
- Automatic certificate renewal required
- Public-facing applications

**Requirements:**
- Own a domain name
- DNS management access
- Public internet access for ACME challenge

**Configuration:**
```hcl
enable_cert_manager = true
letsencrypt_email = "admin@yourdomain.com"
enable_letsencrypt_staging = true  # Start with staging
ssl_certificate_subject = "yourdomain.com"
ssl_certificate_dns_names = ["yourdomain.com", "*.yourdomain.com"]
```

**Validation Steps:**
1. Verify domain ownership
2. Test with staging environment first
3. Switch to production after validation

### Option 2: Wildcard Certificates (Manual Management)

**Best for:**
- Enterprise environments with existing PKI
- Multiple subdomains
- Offline or air-gapped environments

**Requirements:**
- Certificate authority access
- Manual certificate renewal process
- Azure Key Vault for storage

**Configuration:**
```hcl
create_demo_ssl_certificate = false
# Import existing certificate to Key Vault
# Configure Application Gateway to use Key Vault certificate
```

### Option 3: Self-Signed Certificates (Development Only)

**Best for:**
- Development and testing
- Proof of concept deployments
- No domain requirements

**Configuration:**
```hcl
create_demo_ssl_certificate = true
```

## Deployment Timeline

### Typical Deployment Duration
- **Azure setup scripts**: 5-10 minutes
- **Terraform infrastructure**: 15-20 minutes
- **Platform services**: 5-10 minutes
- **Application deployment**: 5-10 minutes
- **Total**: 30-50 minutes

### Critical Path Dependencies
1. Azure service principal creation
2. Storage account for Terraform state
3. AKS cluster provisioning
4. Application Gateway configuration
5. Certificate management setup
6. ArgoCD installation
7. Application deployment

## Validation Checkpoints

### After Azure Setup
```bash
# Verify service principal
az ad sp show --id $ARM_CLIENT_ID

# Verify storage account
az storage account show --name <storage-account-name>

# Verify permissions
az role assignment list --assignee $ARM_CLIENT_ID
```

### After Infrastructure Deployment
```bash
# Verify AKS cluster
az aks show --resource-group rg-your-project-dev --name aks-your-project-dev

# Verify Application Gateway
az network application-gateway show --resource-group rg-your-project-dev --name agw-your-project-dev

# Verify Key Vault
az keyvault show --name kv-your-project-dev
```

### After Platform Deployment
```bash
# Verify ArgoCD
kubectl get pods -n argocd

# Verify monitoring
kubectl get pods -n monitoring

# Verify certificates
kubectl get certificates -A
```

## Common Issues and Solutions

### Azure Quota Issues
**Problem**: Insufficient quota for AKS nodes or Application Gateway
**Solution**: Request quota increase in Azure portal

### DNS Resolution Issues
**Problem**: Let's Encrypt challenges fail
**Solution**: Verify DNS configuration and public accessibility

### Certificate Issues
**Problem**: SSL certificates not working
**Solution**: Check Key Vault permissions and certificate format

### GitHub Actions Failures
**Problem**: Pipeline fails with authentication errors
**Solution**: Verify GitHub secrets are correctly configured

## Cost Estimation

### Minimum Viable Deployment
- **AKS cluster**: ~$150/month
- **Application Gateway**: ~$50/month
- **Storage and networking**: ~$20/month
- **Total**: ~$220/month

### Production-Ready Deployment
- **AKS cluster with HA**: ~$400/month
- **Application Gateway with WAF**: ~$100/month
- **Monitoring and logging**: ~$50/month
- **Total**: ~$550/month

## Next Steps After Deployment

1. **Configure DNS** - Point your domain to Application Gateway IP
2. **Set up monitoring alerts** - Configure Grafana dashboards and alerts
3. **Deploy applications** - Use ArgoCD to deploy your applications
4. **Security hardening** - Review and implement additional security measures
5. **Backup strategy** - Configure backup for persistent data
6. **Disaster recovery** - Plan for multi-region deployment if needed

## Validation Summary

### Validated Components

#### Scripts and Automation
- [x] `scripts/setup-azure-credentials.sh` - Comprehensive Azure setup with error handling
- [x] `scripts/setup-github-secrets.sh` - Automated GitHub secrets configuration
- [x] GitHub Actions workflows - Complete CI/CD pipeline for infrastructure and applications
- [x] Terraform modules - Modular, reusable infrastructure components

#### Documentation
- [x] `docs/greenfield-setup-guide.md` - Step-by-step guide for new Azure users
- [x] `docs/pipeline-deployment-guide.md` - Complete pipeline-based deployment
- [x] `docs/certificate-management-guide.md` - Comprehensive certificate options
- [x] `docs/architecture.md` - Updated with working Mermaid diagrams

#### Certificate Management
- [x] Let's Encrypt integration with cert-manager
- [x] Self-signed certificates for development
- [x] Wildcard certificate support
- [x] Azure Key Vault integration

### Deployment Options Validated

#### Option 1: Fully Automated Pipeline (Recommended)
**Time to deployment**: 30-50 minutes
**Skill level**: Beginner to Intermediate
**Best for**: Teams wanting minimal manual intervention

#### Option 2: Manual Step-by-Step
**Time to deployment**: 60-90 minutes
**Skill level**: Intermediate to Advanced
**Best for**: Teams wanting to understand each component

### Pre-Deployment Checklist

#### Azure Prerequisites
- [ ] Azure subscription with sufficient quota
- [ ] Account permissions: Contributor + User Access Administrator + Key Vault Administrator
- [ ] Azure CLI installed and authenticated
- [ ] Subscription ID and tenant ID available

#### Local Environment
- [ ] All required tools installed (see prerequisites)
- [ ] GitHub repository forked/cloned
- [ ] GitHub CLI authenticated
- [ ] Bash shell available

#### Certificate Decision Made
- [ ] Domain ownership confirmed (for Let's Encrypt)
- [ ] Certificate approach selected (Let's Encrypt/Self-signed/Wildcard)
- [ ] DNS configuration planned

## Support and Troubleshooting

### Documentation Resources
- `docs/troubleshooting.md` - Common issues and solutions
- `docs/pipeline-deployment-guide.md` - Pipeline-specific guidance
- `docs/certificate-management-guide.md` - Certificate troubleshooting
- GitHub Actions logs - Detailed deployment information

### Debugging Tools
- Azure portal - Resource health and configuration
- kubectl - Kubernetes cluster debugging
- Terraform state - Infrastructure state management
- ArgoCD UI - Application deployment status
