# Troubleshooting Guide

This guide covers common issues and solutions for the Azure AKS GitOps platform.

## Setup and Configuration Issues

### Environment Isolation and Security

#### Problem: Script exits with "Environment must be specified explicitly"

**Symptoms:**
```
[ERROR] Environment must be specified explicitly for security.
Use one of:
  --environment dev                    # Setup single environment
  --environment staging                # Setup single environment
  --environment prod                   # Setup single environment
  --all-environments                   # Setup all environments
```

**Solution:**
This is intentional security behavior. Always specify the environment explicitly:

```bash
# For development environment
./scripts/setup-azure-credentials.sh --environment dev

# For staging environment
./scripts/setup-azure-credentials.sh --environment staging

# For production environment
./scripts/setup-azure-credentials.sh --environment prod

# Only if you have permissions for all environments
./scripts/setup-azure-credentials.sh --all-environments
```

**Why this is required:**
- Prevents accidentally creating resources in wrong environments
- Ensures proper isolation between dev/staging/prod
- Follows security best practices for multi-tenant scenarios
- Protects against resource sprawl and unexpected costs

#### Problem: Wrong environment resources created

**Symptoms:**
- Resources created in unexpected Azure subscription
- Storage accounts created for environments you don't manage
- Permission errors when accessing resources

**Prevention:**
- Always use `--environment` flag with specific environment
- Verify Azure subscription before running setup: `az account show`
- Use separate Azure subscriptions for different environments when possible
- Review generated `.env` and `backend.conf` files before proceeding

### Python Environment Issues

#### Problem: `check-python-env.py` reports missing packages even after installation

**Symptoms:**
```
[WARNING] Missing packages (3):
  ERROR azure-cli
  ERROR pyyaml
  ERROR python-dateutil
```

**Solution:**
This was a bug in the package detection script. The issue is now fixed, but if you encounter it:

1. Verify packages are actually installed:
   ```bash
   source venv/bin/activate
   pip list | grep -E "(azure-cli|PyYAML|python-dateutil)"
   ```

2. If packages are installed but not detected, update the script or reinstall:
   ```bash
   make install-deps
   python3 scripts/check-python-env.py
   ```

#### Problem: Virtual environment not activated

**Symptoms:**
```
[WARNING] Virtual environment: Not active
```

**Solution:**
```bash
source venv/bin/activate
# Verify activation
python3 scripts/check-python-env.py
```

### Terraform Backend Issues

#### Problem: "Backend configuration changed" error

**Symptoms:**
```
Error: Backend configuration changed
A change in the backend configuration has been detected, which may require migrating existing state.
```

**Solution:**
Use the `-reconfigure` flag to safely handle backend changes:
```bash
terraform -chdir=terraform init -reconfigure -backend-config="environments/dev/backend.conf"
```

**Why this happens:**
- Previous Terraform state exists with different backend configuration
- Backend storage account or container names changed
- Switching between environments

#### Problem: Environment variables not loaded

**Symptoms:**
- Terraform authentication errors
- "ARM_CLIENT_ID not set" errors

**Solution:**
```bash
# Load environment variables (required for each new terminal session)
source .env

# Verify variables are set
echo $ARM_CLIENT_ID
echo $ARM_SUBSCRIPTION_ID
```

### Azure Setup Issues

#### Problem: Resource providers not registered

**Symptoms:**
```
The subscription is not registered to use namespace 'Microsoft.ContainerService'
```

**Solution:**
The setup script should handle this automatically, but if needed:
```bash
az provider register --namespace Microsoft.ContainerService
az provider register --namespace Microsoft.ContainerRegistry
az provider register --namespace Microsoft.Network
```

## Quick Diagnostic Commands

### **Platform Health Check**
```bash
# Check overall cluster health
kubectl get nodes
kubectl get pods --all-namespaces | grep -v Running

# Check critical services
kubectl get pods -n argocd
kubectl get pods -n monitoring
kubectl get pods -n ai-tools

# Check AGC and networking
kubectl get gateways,httproutes -A
kubectl get pods -n azure-alb-system
kubectl get svc --all-namespaces | grep LoadBalancer
```

### **Terraform State Check**
```bash
# Check Terraform state
terraform show
terraform state list

# Validate configuration
terraform validate
terraform plan -detailed-exitcode
```

## Infrastructure Issues

### **Terraform Deployment Failures**

#### **Problem**: "Backend initialization failed"
```bash
# Error: Failed to get existing workspaces
Error: Error loading state: storage account not found
```

**Solution**:
```bash
# Verify Azure authentication
az account show

# Check storage account exists
az storage account show --name <storage-account-name> --resource-group <rg-name>

# Re-run setup script if needed
./scripts/setup-azure-credentials.sh
```

#### **Problem**: "Insufficient permissions"
```bash
# Error: authorization failed
Error: creating AKS Cluster: authorization failed
```

**Solution**:
```bash
# Check service principal permissions
az role assignment list --assignee <service-principal-id>

# Verify required roles
# - Contributor (for resource creation)
# - User Access Administrator (for RBAC)
# - Key Vault Administrator (for certificates)

# Add missing permissions
az role assignment create \
  --assignee <service-principal-id> \
  --role "User Access Administrator" \
  --scope "/subscriptions/<subscription-id>"
```

#### **Problem**: "Resource quota exceeded"
```bash
# Error: quota exceeded
Error: creating Virtual Machine: compute.VirtualMachinesClient#CreateOrUpdate
```

**Solution**:
```bash
# Check current quotas
az vm list-usage --location "East US" --output table

# Request quota increase in Azure portal
# Or use smaller VM sizes in terraform.tfvars
aks_node_vm_size = "Standard_B2s"  # Smaller size
ai_node_vm_size = "Standard_NC4as_T4_v3"  # Smaller GPU VM
```

### **AKS Cluster Issues**

#### **Problem**: "Cluster not accessible"
```bash
# Error: Unable to connect to the server
error: You must be logged in to the server (Unauthorized)
```

**Solution**:
```bash
# Get cluster credentials
az aks get-credentials \
  --resource-group <resource-group> \
  --name <cluster-name> \
  --overwrite-existing

# Verify cluster access
kubectl cluster-info

# Check if cluster is private and you're not in authorized IP range
az aks show --resource-group <rg> --name <cluster> --query "apiServerAccessProfile"
```

#### **Problem**: "Nodes not ready"
```bash
# Node status shows NotReady
NAME                                STATUS     ROLES   AGE   VERSION
aks-default-12345678-vmss000000    NotReady   agent   10m   v1.28.5
```

**Solution**:
```bash
# Check node conditions
kubectl describe node <node-name>

# Common causes and solutions:
# 1. Network connectivity issues
kubectl get pods -n kube-system | grep -E "(coredns|azure-cni)"

# 2. Disk pressure
kubectl top nodes

# 3. Memory pressure
kubectl describe node <node-name> | grep -A 5 "Conditions:"

# Restart problematic nodes
az vmss restart --resource-group <node-resource-group> --name <vmss-name>
```

## Application Issues

### **ArgoCD Problems**

#### **Problem**: "ArgoCD UI not accessible"
```bash
# Cannot access ArgoCD dashboard
```

**Solution**:
```bash
# Check ArgoCD pods
kubectl get pods -n argocd

# Check HTTPRoute configuration (AGC)
kubectl get httproute -n argocd
kubectl describe httproute argocd-server -n argocd

# Check Gateway status
kubectl get gateway -A

# Port forward for direct access
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Check ALB Controller status
kubectl get pods -n azure-alb-system
kubectl logs -n azure-alb-system -l app=alb-controller
```

#### **Problem**: "Applications not syncing"
```bash
# ArgoCD shows "OutOfSync" status
```

**Solution**:
```bash
# Check application status
kubectl get applications -n argocd
kubectl describe application <app-name> -n argocd

# Manual sync
argocd app sync <app-name>

# Check repository connectivity
argocd repo list
argocd repo get <repo-url>

# Verify RBAC permissions
kubectl auth can-i create deployments --as=system:serviceaccount:argocd:argocd-application-controller
```

### **Monitoring Stack Issues**

#### **Problem**: "Prometheus not scraping metrics"
```bash
# Targets showing as down in Prometheus UI
```

**Solution**:
```bash
# Check Prometheus configuration
kubectl get configmap prometheus-config -n monitoring -o yaml

# Verify service discovery
kubectl get servicemonitor -n monitoring
kubectl get endpoints -n monitoring

# Check network policies
kubectl get networkpolicy -n monitoring

# Restart Prometheus
kubectl rollout restart statefulset prometheus-prometheus -n monitoring
```

#### **Problem**: "Grafana dashboards not loading"
```bash
# Dashboards show "No data" or fail to load
```

**Solution**:
```bash
# Check Grafana data sources
kubectl exec -n monitoring deployment/prometheus-grafana -- \
  curl -s http://localhost:3000/api/datasources

# Verify Prometheus connectivity
kubectl exec -n monitoring deployment/prometheus-grafana -- \
  curl -s http://prometheus-server:80/api/v1/query?query=up

# Check Grafana logs
kubectl logs -n monitoring deployment/prometheus-grafana
```

### **AI/ML Platform Issues**

#### **Problem**: "JupyterHub pods not starting"
```bash
# User pods stuck in Pending state
```

**Solution**:
```bash
# Check resource availability
kubectl describe pod <jupyter-pod> -n ai-tools

# Common issues:
# 1. Insufficient resources
kubectl top nodes
kubectl describe nodes | grep -A 5 "Allocated resources"

# 2. GPU node not available
kubectl get nodes -l node-type=ai
kubectl describe node <gpu-node>

# 3. Storage issues
kubectl get pvc -n ai-tools
kubectl describe pvc <pvc-name> -n ai-tools

# Scale GPU node pool if needed
az aks nodepool scale \
  --resource-group <rg> \
  --cluster-name <cluster> \
  --name aipool \
  --node-count 1
```

#### **Problem**: "MLflow not accessible"
```bash
# MLflow UI returns 500 errors
```

**Solution**:
```bash
# Check MLflow components
kubectl get pods -n ai-tools | grep mlflow

# Check database connectivity
kubectl exec -n ai-tools deployment/mlflow -- \
  pg_isready -h mlflow-postgresql -p 5432

# Check MinIO storage
kubectl exec -n ai-tools deployment/mlflow-minio -- \
  mc admin info local

# Restart MLflow
kubectl rollout restart deployment/mlflow -n ai-tools
```

## Networking Issues

### **Application Gateway for Containers (AGC) Problems**

#### **Problem**: "502 Bad Gateway errors"
```bash
# Users getting 502 errors when accessing applications
```

**Solution**:
```bash
# Check ALB Controller status
kubectl get pods -n azure-alb-system
kubectl logs -n azure-alb-system -l app=alb-controller

# Check Gateway status
kubectl get gateway -A -o wide
kubectl describe gateway <gateway-name>

# Check HTTPRoute status
kubectl get httproute -A
kubectl describe httproute <route-name> -n <namespace>

# Verify backend targets
kubectl get endpoints -n <namespace>

# Check application pod health
kubectl get pods -n <namespace>
kubectl logs <pod-name> -n <namespace>
```

#### **Problem**: "HTTPRoute not routing traffic"
```bash
# Traffic not reaching backend services
```

**Solution**:
```bash
# Check HTTPRoute is accepted
kubectl get httproute <route-name> -n <namespace> -o yaml

# Verify parentRefs point to correct Gateway
kubectl get gateway -A

# Check backend service exists and has endpoints
kubectl get svc,endpoints -n <namespace>

# Verify AGC association
az network alb association list \
  --resource-group <rg> --alb-name <agc-name>
```

#### **Problem**: "SSL certificate issues"
```bash
# Certificate warnings or SSL errors
```

**Solution**:
```bash
# Check certificate status in Key Vault
az keyvault certificate show --vault-name <vault> --name <cert-name>

# Verify cert-manager if using Let's Encrypt
kubectl get certificates -A
kubectl describe certificate <cert-name> -n <namespace>

# Check certificate issuer
kubectl get clusterissuer
kubectl describe clusterissuer letsencrypt-prod

# Check Gateway TLS configuration
kubectl get gateway <gateway-name> -o yaml | grep -A 20 tls
```

### **DNS Resolution Issues**

#### **Problem**: "Service discovery not working"
```bash
# Pods cannot resolve service names
```

**Solution**:
```bash
# Check CoreDNS pods
kubectl get pods -n kube-system | grep coredns

# Test DNS resolution
kubectl run -it --rm debug --image=busybox --restart=Never -- nslookup kubernetes.default

# Check DNS configuration
kubectl get configmap coredns -n kube-system -o yaml

# Restart CoreDNS if needed
kubectl rollout restart deployment/coredns -n kube-system
```

## Performance Issues

### **Resource Constraints**

#### **Problem**: "Pods being evicted"
```bash
# Pods showing "Evicted" status
```

**Solution**:
```bash
# Check node resource usage
kubectl top nodes
kubectl describe nodes | grep -A 5 "Allocated resources"

# Check pod resource requests/limits
kubectl describe pod <pod-name> -n <namespace>

# Identify resource-hungry pods
kubectl top pods --all-namespaces --sort-by=memory
kubectl top pods --all-namespaces --sort-by=cpu

# Scale cluster if needed
az aks nodepool scale \
  --resource-group <rg> \
  --cluster-name <cluster> \
  --name <nodepool> \
  --node-count <new-count>
```

### **Storage Performance**

#### **Problem**: "Slow persistent volume performance"
```bash
# Applications experiencing slow I/O
```

**Solution**:
```bash
# Check storage class
kubectl get storageclass

# Verify disk performance tier
az disk list --resource-group <node-rg> --output table

# Consider upgrading to Premium SSD
# Update storage class in application manifests
storageClassName: managed-premium
```

## Security Issues

### **RBAC Problems**

#### **Problem**: "Permission denied errors"
```bash
# Users cannot access resources
```

**Solution**:
```bash
# Check user permissions
kubectl auth can-i <verb> <resource> --as=<user>

# List role bindings
kubectl get rolebindings,clusterrolebindings --all-namespaces

# Check ArgoCD RBAC
kubectl get configmap argocd-rbac-cm -n argocd -o yaml

# Verify Azure AD integration
kubectl get pods -n argocd | grep dex
kubectl logs <dex-pod> -n argocd
```

### **Network Policy Issues**

#### **Problem**: "Services cannot communicate"
```bash
# Network policies blocking legitimate traffic
```

**Solution**:
```bash
# Check network policies
kubectl get networkpolicy --all-namespaces

# Test connectivity
kubectl run -it --rm debug --image=busybox --restart=Never -- \
  wget -qO- http://<service>.<namespace>:8080

# Temporarily disable network policies for testing
kubectl delete networkpolicy <policy-name> -n <namespace>
```

## Disaster Recovery

### **Backup and Restore**

#### **Problem**: "Need to restore from backup"
```bash
# Cluster or data corruption requiring restore
```

**Solution**:
```bash
# For Terraform state
az storage blob download \
  --account-name <storage-account> \
  --container-name tfstate \
  --name terraform.tfstate.backup \
  --file terraform.tfstate

# For persistent volumes
# Use Velero for cluster backups
velero backup get
velero restore create --from-backup <backup-name>

# For databases
kubectl exec <postgres-pod> -- pg_dump <database> > backup.sql
```

## Getting Help

### **Log Collection**

#### **Comprehensive Log Gathering**
```bash
#!/bin/bash
# Collect diagnostic information

echo "=== Cluster Info ===" > debug.log
kubectl cluster-info >> debug.log

echo "=== Node Status ===" >> debug.log
kubectl get nodes -o wide >> debug.log

echo "=== Pod Status ===" >> debug.log
kubectl get pods --all-namespaces >> debug.log

echo "=== Events ===" >> debug.log
kubectl get events --all-namespaces --sort-by='.lastTimestamp' >> debug.log

echo "=== Terraform State ===" >> debug.log
terraform show >> debug.log
```

### **Support Channels**

1. **GitHub Issues**: Create detailed issue with logs
2. **Azure Support**: For Azure-specific problems
3. **Community Forums**: Kubernetes, ArgoCD, Terraform communities
4. **Documentation**: Check all guides in `docs/` directory

### **Escalation Process**

1. **Level 1**: Check this troubleshooting guide
2. **Level 2**: Review application logs and events
3. **Level 3**: Collect comprehensive diagnostics
4. **Level 4**: Engage vendor support (Azure, etc.)
5. **Level 5**: Consider professional services

Remember to always test solutions in a development environment before applying to production!
