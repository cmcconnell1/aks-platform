# Setup Without Domain Guide

This guide explains how to set up and test the Azure AKS GitOps platform when you don't have a domain name or Azure DNS zone yet.

## Overview

You can fully test and use this platform without owning a domain by using:
- Demo SSL certificates (self-signed)
- Local hosts file for DNS resolution
- Application Gateway for Containers (AGC) frontend FQDN for access

## Quick Setup (No Domain)

### Step 1: Use Demo Certificate Configuration

In your `terraform.tfvars` file:

```hcl
# Use demo certificates (self-signed)
create_demo_ssl_certificate = true
ssl_certificate_subject = "aks-platform.local"
ssl_certificate_dns_names = ["aks-platform.local", "*.aks-platform.local"]

# Disable Let's Encrypt (requires real domain)
enable_cert_manager = false

# Other settings
project_name = "aks-platform"
environment = "dev"
location = "East US"
authorized_ip_ranges = ["your.public.ip.address/32"]
```

### Step 2: Deploy Infrastructure

```bash
# Deploy with demo certificates
terraform apply -var-file=environments/dev/terraform.tfvars
```

### Step 3: Get AGC Frontend FQDN

```bash
# Get the AGC frontend FQDN
terraform output agc_frontend_fqdn
# Example output: abc123.eastus.alb.azure.com

# Get the resolved IP address
nslookup $(terraform output -raw agc_frontend_fqdn)
# Example output: 20.123.45.67
```

### Step 4: Configure Local DNS (Hosts File)

First, resolve the AGC FQDN to get the IP address:
```bash
# Get the IP from the FQDN
AGC_IP=$(nslookup $(terraform output -raw agc_frontend_fqdn) | grep -A1 "Name:" | grep Address | awk '{print $2}')
echo $AGC_IP
```

**Linux/macOS:**
```bash
# Edit hosts file
sudo nano /etc/hosts

# Add these lines (replace with your actual IP from AGC)
20.123.45.67 argocd.aks-platform.local
20.123.45.67 grafana.aks-platform.local
20.123.45.67 jupyter.aks-platform.local
20.123.45.67 mlflow.aks-platform.local
```

**Windows:**
```powershell
# Run as Administrator
notepad C:\Windows\System32\drivers\etc\hosts

# Add these lines (replace with your actual IP from AGC)
20.123.45.67 argocd.aks-platform.local
20.123.45.67 grafana.aks-platform.local
20.123.45.67 jupyter.aks-platform.local
20.123.45.67 mlflow.aks-platform.local
```

### Step 5: Access Applications

Now you can access all applications:

- **ArgoCD**: https://argocd.aks-platform.local
- **Grafana**: https://grafana.aks-platform.local
- **JupyterHub**: https://jupyter.aks-platform.local
- **MLflow**: https://mlflow.aks-platform.local

**Note**: Your browser will show SSL warnings because the certificates are self-signed. This is expected and safe for testing.

## Browser SSL Warnings

### Accept Self-Signed Certificates

When accessing applications, you'll see SSL warnings:

**Chrome/Edge:**
1. Click "Advanced"
2. Click "Proceed to [site] (unsafe)"

**Firefox:**
1. Click "Advanced"
2. Click "Accept the Risk and Continue"

**Safari:**
1. Click "Show Details"
2. Click "visit this website"
3. Click "Visit Website"

### Alternative: Use HTTP Only (Optional)

If SSL warnings are problematic, you can configure the Gateway to use HTTP only:

```yaml
# Update the Gateway listener to use HTTP instead of HTTPS
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
spec:
  listeners:
    - name: http
      protocol: HTTP
      port: 80
      allowedRoutes:
        namespaces:
          from: All
```

Then access via HTTP:
- http://argocd.aks-platform.local
- http://grafana.aks-platform.local

## Upgrading to Real Domain Later

When you're ready to use a real domain:

### Step 1: Get a Domain

**Free Options:**
- **Duck DNS** (duckdns.org) - Free subdomains
- **Freenom** (.tk, .ml, .ga domains)
- **No-IP** - Dynamic DNS service

**Paid Options:**
- **Namecheap** - Cheap domains (~$10/year)
- **GoDaddy** - Popular registrar
- **Cloudflare** - Domain + DNS management

### Step 2: Update Configuration

```hcl
# Switch to real domain
create_demo_ssl_certificate = false
ssl_certificate_subject = "yourdomain.com"
ssl_certificate_dns_names = ["yourdomain.com", "*.yourdomain.com"]

# Enable Let's Encrypt
enable_cert_manager = true
letsencrypt_email = "admin@yourdomain.com"
enable_letsencrypt_staging = true  # Start with staging
```

### Step 3: Update DNS

Point your domain to the AGC frontend FQDN:

```bash
# Create DNS CNAME records pointing to AGC frontend
yourdomain.com        CNAME abc123.eastus.alb.azure.com
*.yourdomain.com      CNAME abc123.eastus.alb.azure.com

# Or create A records if you need to
# First get the IP from the FQDN
nslookup $(terraform output -raw agc_frontend_fqdn)
```

### Step 4: Redeploy

```bash
terraform apply -var-file=environments/dev/terraform.tfvars
```

## Team Access (Multiple Developers)

### Option 1: Shared Hosts File

Share the AGC frontend IP (resolved from FQDN) with your team:

```bash
# Each team member adds to their hosts file
20.123.45.67 argocd.aks-platform.local
20.123.45.67 grafana.aks-platform.local
20.123.45.67 jupyter.aks-platform.local
20.123.45.67 mlflow.aks-platform.local
```

### Option 2: Use Free Dynamic DNS

Set up a free subdomain that everyone can use:

1. **Register at Duck DNS**: duckdns.org
2. **Create subdomain**: `myteam-aks.duckdns.org`
3. **Point to AGC frontend IP** (resolve the FQDN first)
4. **Update terraform.tfvars**:
   ```hcl
   ssl_certificate_subject = "myteam-aks.duckdns.org"
   ssl_certificate_dns_names = ["myteam-aks.duckdns.org", "*.myteam-aks.duckdns.org"]
   ```

### Option 3: Use nip.io (Wildcard DNS)

nip.io provides wildcard DNS for any IP:

```hcl
# Use nip.io format: anything.IP.nip.io
ssl_certificate_subject = "aks.20.123.45.67.nip.io"
ssl_certificate_dns_names = ["aks.20.123.45.67.nip.io", "*.20.123.45.67.nip.io"]
```

Access applications:
- https://argocd.20.123.45.67.nip.io
- https://grafana.20.123.45.67.nip.io

## Troubleshooting

### Can't Access Applications

1. **Check AGC Frontend FQDN**:
   ```bash
   terraform output agc_frontend_fqdn
   ```

2. **Verify hosts file**:
   ```bash
   # Test DNS resolution
   nslookup argocd.aks-platform.local
   ping argocd.aks-platform.local
   ```

3. **Check AGC health**:
   ```bash
   # Check ALB Controller status
   kubectl get pods -n azure-alb-system

   # Check Gateway status
   kubectl get gateway -A

   # Check HTTPRoutes
   kubectl get httproutes -A
   ```

### SSL Certificate Issues

1. **Check certificate in Key Vault**:
   ```bash
   az keyvault certificate list --vault-name $(terraform output -raw key_vault_name)
   ```

2. **Verify cert-manager certificates**:
   ```bash
   kubectl get certificates -A
   kubectl describe certificate -A
   ```

3. **Check Gateway TLS configuration**:
   ```bash
   kubectl get gateway -A -o yaml | grep -A 20 tls
   ```

### Hosts File Not Working

**Linux/macOS:**
```bash
# Check hosts file syntax
cat /etc/hosts | grep aks-platform

# Clear DNS cache
sudo dscacheutil -flushcache  # macOS
sudo systemctl restart systemd-resolved  # Ubuntu
```

**Windows:**
```powershell
# Check hosts file
type C:\Windows\System32\drivers\etc\hosts | findstr aks-platform

# Clear DNS cache
ipconfig /flushdns
```

## Security Considerations

### Local Development

- Self-signed certificates are safe for local testing
- Don't use demo certificates in production
- Restrict access with `authorized_ip_ranges`

### Network Security

```hcl
# Limit access to your IP only
authorized_ip_ranges = ["your.public.ip.address/32"]

# Or your office network
authorized_ip_ranges = ["203.0.113.0/24"]
```

### Application Security

- Change default passwords immediately
- Enable proper authentication in applications
- Use strong passwords for ArgoCD, Grafana, etc.

## Cost Optimization

### Free Tier Usage

- Use Azure free tier for testing
- Monitor costs in Azure portal
- Set up budget alerts

### Resource Sizing

```hcl
# Use smaller instances for testing
aks_node_vm_size = "Standard_B2s"  # Cheaper than Standard_D2s_v3
aks_node_count = 1                 # Minimum for testing
enable_ai_node_pool = false        # Disable GPU nodes if not needed
```

## Next Steps

1. **Explore Applications**: Test ArgoCD, Grafana, JupyterHub
2. **Deploy Sample Apps**: Use ArgoCD to deploy applications
3. **Learn GitOps**: Practice with application deployments
4. **Plan Production**: Consider domain purchase and Let's Encrypt
5. **Scale Up**: Add more node pools, enable AI tools

## Useful Commands

```bash
# Get all important outputs
terraform output

# Check cluster status
kubectl get nodes
kubectl get pods --all-namespaces

# Access applications via port-forward (alternative to hosts file)
kubectl port-forward -n argocd svc/argocd-server 8080:443
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80

# Get application passwords
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
kubectl get secret --namespace monitoring prometheus-grafana -o jsonpath="{.data.admin-password}" | base64 --decode
```

This approach lets you fully experience the platform without any external dependencies or costs beyond Azure resources!
