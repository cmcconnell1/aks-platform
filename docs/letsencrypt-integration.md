# Let's Encrypt Integration Guide

This guide explains how to integrate Let's Encrypt with the Azure AKS GitOps platform for automatic SSL certificate management.

## Overview

The project supports automatic SSL certificate provisioning using:
- **cert-manager** - Kubernetes certificate management controller
- **Let's Encrypt** - Free, automated certificate authority
- **Azure Application Gateway** - SSL termination and ingress
- **Azure Key Vault** - Secure certificate storage

## Integration Options

### Option 1: cert-manager with Application Gateway (Recommended)

This approach uses cert-manager to automatically provision Let's Encrypt certificates and integrates them with Azure Application Gateway.

**Benefits:**
- Automatic certificate renewal
- Azure-native integration
- Secure storage in Key Vault
- Works with existing Application Gateway setup

### Option 2: External DNS + cert-manager

For environments with external DNS management or wildcard certificate requirements.

## Configuration

### Step 1: Enable cert-manager

Update your `terraform.tfvars` file:

```hcl
# Enable cert-manager
enable_cert_manager = true

# Let's Encrypt configuration
letsencrypt_email = "admin@yourdomain.com"
enable_letsencrypt_staging = true   # Start with staging for testing
enable_letsencrypt_prod = false     # Enable after testing

# Your actual domain (not the demo certificate)
create_demo_ssl_certificate = false
ssl_certificate_subject = "yourdomain.com"
ssl_certificate_dns_names = ["yourdomain.com", "*.yourdomain.com"]
```

### Step 2: Deploy Infrastructure

```bash
# Deploy with cert-manager enabled
terraform apply -var-file=environments/dev/terraform.tfvars
```

This creates:
- cert-manager namespace and deployment
- Let's Encrypt ClusterIssuers (staging and/or production)
- Managed identity for cert-manager with Key Vault permissions

### Step 3: Configure DNS

Point your domain to the Application Gateway public IP:

```bash
# Get the Application Gateway IP
terraform output application_gateway_public_ip

# Create DNS A records
yourdomain.com        -> <APP_GATEWAY_IP>
*.yourdomain.com      -> <APP_GATEWAY_IP>
```

### Step 4: Request Certificates

Create Certificate resources for your applications:

```yaml
# argocd-certificate.yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: argocd-tls
  namespace: argocd
spec:
  secretName: argocd-tls
  issuerRef:
    name: letsencrypt-staging  # Use letsencrypt-prod when ready
    kind: ClusterIssuer
  dnsNames:
    - argocd.yourdomain.com
```

```yaml
# grafana-certificate.yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: grafana-tls
  namespace: monitoring
spec:
  secretName: grafana-tls
  issuerRef:
    name: letsencrypt-staging
    kind: ClusterIssuer
  dnsNames:
    - grafana.yourdomain.com
```

### Step 5: Update Ingress Resources

Update your ingress resources to use the certificates:

```yaml
# Example: ArgoCD ingress with Let's Encrypt
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argocd-server-ingress
  namespace: argocd
  annotations:
    kubernetes.io/ingress.class: azure/application-gateway
    appgw.ingress.kubernetes.io/ssl-redirect: "true"
    cert-manager.io/cluster-issuer: letsencrypt-staging
spec:
  tls:
    - hosts:
        - argocd.yourdomain.com
      secretName: argocd-tls
  rules:
    - host: argocd.yourdomain.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: argocd-server
                port:
                  number: 80
```

## Testing and Validation

### Step 1: Test with Staging

Always start with Let's Encrypt staging to avoid rate limits:

```bash
# Check certificate status
kubectl get certificates -A

# Check certificate details
kubectl describe certificate argocd-tls -n argocd

# Check cert-manager logs
kubectl logs -n cert-manager deployment/cert-manager
```

### Step 2: Validate Certificate

```bash
# Test the certificate
curl -I https://argocd.yourdomain.com

# Check certificate details
openssl s_client -connect argocd.yourdomain.com:443 -servername argocd.yourdomain.com
```

### Step 3: Switch to Production

Once staging works, switch to production:

```hcl
# In terraform.tfvars
enable_letsencrypt_staging = false
enable_letsencrypt_prod = true
```

Update your Certificate resources:

```yaml
spec:
  issuerRef:
    name: letsencrypt-prod  # Changed from staging
    kind: ClusterIssuer
```

## Advanced Configuration

### Wildcard Certificates with DNS01

For wildcard certificates, you need DNS01 challenge solver:

```hcl
# In terraform.tfvars (requires Azure DNS zone)
enable_dns01_solver = true
dns_resource_group_name = "dns-rg"
dns_zone_name = "yourdomain.com"
```

Create wildcard certificate:

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: wildcard-tls
  namespace: default
spec:
  secretName: wildcard-tls
  issuerRef:
    name: letsencrypt-dns01
    kind: ClusterIssuer
  dnsNames:
    - "*.yourdomain.com"
    - "yourdomain.com"
```

### Certificate Monitoring

Monitor certificate expiration:

```bash
# Check certificate expiration
kubectl get certificates -A -o custom-columns=NAME:.metadata.name,NAMESPACE:.metadata.namespace,READY:.status.conditions[0].status,EXPIRY:.status.notAfter

# Set up alerts in Grafana for certificate expiration
```

## Troubleshooting

### Common Issues

**Certificate Pending**:
```bash
# Check certificate status
kubectl describe certificate <cert-name> -n <namespace>

# Check cert-manager logs
kubectl logs -n cert-manager deployment/cert-manager

# Check challenge status
kubectl get challenges -A
```

**DNS Validation Failing**:
```bash
# Verify DNS resolution
nslookup yourdomain.com
dig yourdomain.com

# Check if domain points to Application Gateway IP
```

**Rate Limiting**:
- Let's Encrypt has rate limits (50 certificates per domain per week)
- Always test with staging first
- Use wildcard certificates to reduce certificate count

**Application Gateway Integration**:
```bash
# Check AGIC logs
kubectl logs -n kube-system -l app=ingress-appgw

# Verify ingress configuration
kubectl get ingress -A
```

### Debugging Commands

```bash
# cert-manager status
kubectl get pods -n cert-manager
kubectl get clusterissuers
kubectl get certificates -A

# Certificate details
kubectl describe certificate <name> -n <namespace>
kubectl get certificaterequests -A
kubectl get orders -A
kubectl get challenges -A

# cert-manager logs
kubectl logs -n cert-manager deployment/cert-manager
kubectl logs -n cert-manager deployment/cert-manager-webhook
kubectl logs -n cert-manager deployment/cert-manager-cainjector
```

## Best Practices

### Security
1. **Use staging first** - Always test with Let's Encrypt staging
2. **Monitor expiration** - Set up alerts for certificate expiration
3. **Rotate regularly** - Let cert-manager handle automatic renewal
4. **Secure storage** - Certificates are stored in Kubernetes secrets

### Operations
1. **Backup certificates** - Include certificate secrets in backup strategy
2. **Monitor rate limits** - Be aware of Let's Encrypt rate limits
3. **Use wildcard certs** - Reduce certificate count with wildcards
4. **Automate everything** - Let cert-manager handle the lifecycle

### Performance
1. **Cache certificates** - Application Gateway caches certificates
2. **Use HTTP01 for simple cases** - Faster than DNS01 for single domains
3. **Use DNS01 for wildcards** - Required for wildcard certificates

## Migration from Manual Certificates

### Step 1: Prepare
1. Document current certificate setup
2. Note expiration dates
3. Plan migration during maintenance window

### Step 2: Deploy cert-manager
1. Deploy cert-manager alongside existing setup
2. Test with staging certificates
3. Validate certificate provisioning

### Step 3: Switch Over
1. Update ingress resources to use new certificates
2. Remove old certificate configuration
3. Monitor for issues

### Step 4: Cleanup
1. Remove old certificate files
2. Update documentation
3. Set up monitoring and alerts

## Cost Considerations

- **Let's Encrypt**: Free certificates
- **cert-manager**: No additional cost (runs on existing cluster)
- **Azure Key Vault**: Minimal cost for certificate storage
- **Application Gateway**: Existing cost, no additional charges for SSL

## Support and Resources

- [cert-manager Documentation](https://cert-manager.io/docs/)
- [Let's Encrypt Documentation](https://letsencrypt.org/docs/)
- [Azure Application Gateway AGIC](https://docs.microsoft.com/en-us/azure/application-gateway/ingress-controller-overview)
- [Kubernetes Ingress](https://kubernetes.io/docs/concepts/services-networking/ingress/)
