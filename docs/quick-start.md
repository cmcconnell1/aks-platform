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
git clone <your-repo-url>
cd aks-platform
chmod +x scripts/*.sh
```

### 2. Azure Authentication

```bash
az login
az account set --subscription "your-subscription-id"
```

### 3. Automated Azure Setup

Choose your preferred script:

```bash
# Option A: Bash script (recommended)
./scripts/setup-azure-credentials.sh

# Option B: Python script (alternative)
./scripts/setup-azure-credentials.py
```

This creates:
- Storage accounts for Terraform state
- Service principals with proper permissions
- Backend configuration files
- Environment-specific variable files

### 4. GitHub Setup

```bash
gh auth login
./scripts/setup-github-secrets.sh
```

This configures:
- Azure credentials as GitHub secrets
- Optional integrations (Infracost, Slack)
- Environment protection guidance

### 5. Configure Your Environment

Edit the generated configuration:

```bash
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

### 6. Deploy via GitHub Actions

```bash
git add .
git commit -m "Initial infrastructure configuration"
git push origin main
```

Or create a pull request for review:

```bash
git checkout -b feature/initial-setup
git add .
git commit -m "Initial infrastructure configuration"
git push origin feature/initial-setup
# Create PR in GitHub UI
```

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
