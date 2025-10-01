# Quick Start Guide

Get your Azure AKS platform up and running in minutes with automated setup scripts.

> **New to Azure?** Check out the [Greenfield Setup Guide](greenfield-setup-guide.md) for comprehensive instructions including Azure account setup, permissions, and cost considerations.

## Prerequisites

### Domain Options

**No Domain Yet?** No problem! Choose your approach:

1. **Local Development** - Use demo certificates + hosts file (fastest)
2. **Free Domain** - Use services like Duck DNS or Freenom (good for testing)
3. **Real Domain** - Buy domain + Azure DNS (production-like)

See configuration examples below for each option.

### Install Required Tools

```bash
# macOS
brew install azure-cli terraform kubectl helm gh jq

# Ubuntu/Debian
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
# Install other tools following their official documentation

# Windows (use WSL2 or Git Bash)
# Install WSL2: wsl --install
# Then use Ubuntu/Debian commands above
```

## 5-Minute Setup

### 1. Clone and Prepare

```bash
git clone git@github.com:cmcconnell1/aks-platform.git
cd aks-platform
chmod +x scripts/*.sh
```

### 2. Python Environment Setup

```bash
# Set up virtual environment with dependencies
./scripts/setup-python-env.sh

# Activate virtual environment
source venv/bin/activate

# Install/update all required dependencies
make install-deps

# Verify setup (should show all packages installed)
python3 scripts/check-python-env.py
```

**Expected output**: All required packages should show as installed:
- OK azure-cli
- OK requests
- OK pyyaml
- OK click
- OK colorama
- OK tabulate
- OK python-dateutil

### 3. Azure Authentication

```bash
az login
az account set --subscription "your-subscription-id"
```

### 4. Automated Azure Setup

**Important**: Environment must be explicitly specified for security.

Choose your preferred script:

```bash
# Option A: Bash script (recommended) - specify environment explicitly
./scripts/setup-azure-credentials.sh --environment dev

# Option B: Python script (alternative) - specify environment explicitly
./scripts/setup-azure-credentials.py --environment dev

# For multiple environments (only if you have permissions)
./scripts/setup-azure-credentials.sh --all-environments
```

**Why explicit environment specification?**
- Prevents accidentally creating resources in unintended environments
- Ensures proper isolation between dev/staging/prod
- Follows security best practices for multi-environment setups

This creates:
- Storage accounts for Terraform state
- Service principals with proper permissions
- Backend configuration files (`terraform/environments/*/backend.conf`)
- GitHub Actions credentials (`github-actions-credentials.json`)
- Environment variables file (`.env`)

**Important**:
- **Backend config files** (`backend.conf`) - Safe to commit, contain non-sensitive configuration
- **Credential files** (`.env`, `github-actions-credentials.json`) - Contain secrets, never committed
- **GitHub secrets** - Configured securely via `setup-github-secrets.sh` script

### 5. Load Environment Variables

After Azure setup completes, load the generated environment variables:

```bash
# Source the environment variables (required for Terraform)
source .env
```

**Note**: You'll need to run `source .env` in each new terminal session.

### 6. GitHub Setup (Optional)

If you plan to use GitHub Actions for CI/CD:

```bash
gh auth login
./scripts/setup-github-secrets.sh
```

This configures:
- Azure credentials as GitHub secrets
- Optional integrations (Infracost, Slack)
- Environment protection guidance

### 7. Initialize Terraform

Initialize Terraform with the Azure backend for your specific environment:

```bash
# Initialize Terraform with the generated backend configuration (replace 'dev' with your environment)
terraform -chdir=terraform init -reconfigure -backend-config="environments/dev/backend.conf"

# For other environments:
# terraform -chdir=terraform init -reconfigure -backend-config="environments/staging/backend.conf"
# terraform -chdir=terraform init -reconfigure -backend-config="environments/prod/backend.conf"
```

**Expected output**: "Terraform has been successfully initialized!"

**Note**:
- Use `-reconfigure` to handle any backend configuration changes safely
- Replace `dev` with the environment you specified in step 4

### 8. Configure Your Environment

Edit the generated configuration:

```bash
# The setup script automatically generates terraform.tfvars from the example template
# Update with your domain and IP ranges
vim terraform/environments/dev/terraform.tfvars
```

Key settings to update:
```hcl
project_name = "aks-platform"

# Option A: No domain yet (use demo certificates)
create_demo_ssl_certificate = true
ssl_certificate_subject = "aks-platform.local"
ssl_certificate_dns_names = ["aks-platform.local", "*.aks-platform.local"]
enable_cert_manager = false

# Option B: Have a real domain (use Let's Encrypt)
# create_demo_ssl_certificate = false
# ssl_certificate_subject = "your-domain.com"
# ssl_certificate_dns_names = ["your-domain.com", "*.your-domain.com"]
# enable_cert_manager = true
# letsencrypt_email = "admin@your-domain.com"

# Security
authorized_ip_ranges = ["your.public.ip.address/32"]
```

### 9. Validate Setup

Before deploying, validate that everything is configured correctly:

```bash
# Ensure you're in the virtual environment and have environment variables loaded
source venv/bin/activate
source .env

# Validate Terraform configuration
terraform -chdir=terraform validate

# Run a Terraform plan to see what will be created (replace 'dev' with your environment)
terraform -chdir=terraform plan -var-file="environments/dev/terraform.tfvars"

# For other environments:
# terraform -chdir=terraform plan -var-file="environments/staging/terraform.tfvars"
# terraform -chdir=terraform plan -var-file="environments/prod/terraform.tfvars"
```

**Expected output**:
- Terraform validation should pass with no errors
- Plan should show resources to be created (no errors about missing variables or authentication)

### 11. Deploy via GitHub Actions

```bash
git add terraform/environments/*/backend.conf
git commit -m "feat: add Azure backend configuration"
git push origin main
```

Or create a pull request for review:

```bash
git checkout -b feature/initial-setup
git add terraform/environments/*/backend.conf
git commit -m "feat: add Azure backend configuration"
git push origin feature/initial-setup
# Create PR in GitHub UI
```

**Note**: GitHub Actions credentials are securely stored as repository secrets, not committed to the repository.

## What You Get

After deployment, you'll have:

### Core Infrastructure
- **AKS Cluster** with auto-scaling node pools
- **Application Gateway** with WAF and SSL termination
- **Container Registry** with private endpoints
- **Key Vault** for secrets and certificates
- **Virtual Network** with proper segmentation

### Platform Services
- **ArgoCD** for GitOps at `https://argocd.your-domain.com`
- **Grafana** for monitoring at `https://grafana.your-domain.com`
- **JupyterHub** for data science at `https://jupyter.your-domain.com`
- **MLflow** for ML lifecycle at `https://mlflow.your-domain.com`

### AI/ML Capabilities
- **GPU-enabled node pool** for AI workloads
- **NVIDIA GPU Operator** for GPU management
- **JupyterHub** with GPU support
- **MLflow** with PostgreSQL and MinIO backends

## Quick Access

### Get Cluster Credentials

```bash
# Get AKS credentials
az aks get-credentials \
  --resource-group $(terraform output -raw resource_group_name) \
  --name $(terraform output -raw aks_cluster_name)

# Verify access
kubectl get nodes
```

### Access Applications

1. **Get Application Gateway IP**:
   ```bash
   terraform output application_gateway_public_ip
   # Example: 20.123.45.67
   ```

2. **Configure DNS access**:

   **Option A: No domain (local hosts file)**:
   ```bash
   # Edit hosts file (Linux/macOS: /etc/hosts, Windows: C:\Windows\System32\drivers\etc\hosts)
   20.123.45.67 argocd.aks-platform.local
   20.123.45.67 grafana.aks-platform.local
   20.123.45.67 jupyter.aks-platform.local
   20.123.45.67 mlflow.aks-platform.local
   ```

   **Option B: Real domain (DNS records)**:
   ```bash
   # Create DNS A records pointing to Application Gateway IP
   argocd.your-domain.com   -> 20.123.45.67
   grafana.your-domain.com  -> 20.123.45.67
   jupyter.your-domain.com  -> 20.123.45.67
   mlflow.your-domain.com   -> 20.123.45.67
   ```

3. **Get passwords**:
   ```bash
   # ArgoCD admin password
   kubectl -n argocd get secret argocd-initial-admin-secret \
     -o jsonpath="{.data.password}" | base64 -d

   # Grafana admin password
   kubectl get secret --namespace monitoring prometheus-grafana \
     -o jsonpath="{.data.admin-password}" | base64 --decode
   ```

## Development Workflow

### Making Infrastructure Changes

1. **Create feature branch**:
   ```bash
   git checkout -b feature/add-feature
   ```

2. **Make changes** to Terraform files

3. **Test locally** (optional):
   ```bash
   cd terraform
   terraform plan -var-file=environments/dev/terraform.tfvars
   ```

4. **Create pull request**:
   ```bash
   git add .
   git commit -m "Add new feature"
   git push origin feature/add-feature
   ```

5. **Review automated checks** in PR:
   - Terraform plan results
   - Security scan results
   - Cost estimation

6. **Merge after approval** to trigger deployment

### Deploying Applications

Use ArgoCD for application deployments:

1. **Access ArgoCD UI** at `https://argocd.your-domain.com`
2. **Login** with admin credentials
3. **Create applications** pointing to your Git repositories
4. **Configure sync policies** for automated deployments

## Monitoring and Maintenance

### Check System Health

```bash
# Check cluster status
kubectl get nodes
kubectl get pods --all-namespaces

# Check ArgoCD applications
kubectl get applications -n argocd

# Check monitoring stack
kubectl get pods -n monitoring
```

### View Logs

```bash
# Application Gateway Ingress Controller
kubectl logs -n kube-system -l app=ingress-appgw

# ArgoCD
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server

# Grafana
kubectl logs -n monitoring -l app.kubernetes.io/name=grafana
```

### Cost Monitoring

- Review Infracost estimates in PR comments
- Monitor Azure Cost Management dashboard
- Set up budget alerts in Azure portal

## Troubleshooting

### Common Issues

**Python packages not detected**:
```bash
# Ensure virtual environment is activated
source venv/bin/activate
# Install missing dependencies
make install-deps
# Verify installation
python3 scripts/check-python-env.py
```

**Terraform backend configuration changed**:
```bash
# Use -reconfigure to safely handle backend changes
terraform -chdir=terraform init -reconfigure -backend-config="environments/dev/backend.conf"
```

**Environment variables not loaded**:
```bash
# Source the .env file in each new terminal session
source .env
# Verify variables are set
echo $ARM_CLIENT_ID
```

**Can't access applications**:
- Check Application Gateway backend health
- Verify DNS configuration
- Check ingress resources

**ArgoCD not syncing**:
- Verify Git repository access
- Check application configuration
- Review ArgoCD logs

**Pods not starting**:
- Check resource quotas
- Verify node capacity
- Review pod logs and events

### Getting Help

1. **Check documentation** in the `docs/` directory
2. **Review workflow logs** in GitHub Actions
3. **Check Azure portal** for resource status
4. **Use kubectl** for cluster debugging
5. **Create GitHub issues** for persistent problems

## Next Steps

### Production Readiness

1. **Configure custom domain** and SSL certificates
2. **Set up monitoring alerts** in Grafana
3. **Configure backup strategies** for persistent data
4. **Implement security policies** with Azure Policy
5. **Set up disaster recovery** procedures

### Advanced Features

1. **Multi-environment setup** (staging, prod)
2. **Custom ArgoCD applications** for your workloads
3. **Advanced monitoring** with custom dashboards
4. **AI/ML model deployment** using MLflow
5. **Cost optimization** with spot instances and scaling policies

### Integration

1. **Connect to existing systems** (Active Directory, monitoring)
2. **Set up CI/CD pipelines** for applications
3. **Configure external DNS** providers
4. **Integrate with external secrets** management
5. **Set up compliance scanning** and reporting

## Support

- **Documentation**: Check the `docs/` directory for detailed guides
- **Issues**: Create GitHub issues for bugs or feature requests
- **Discussions**: Use GitHub Discussions for questions and ideas
- **Community**: Join relevant Azure and Kubernetes communities
