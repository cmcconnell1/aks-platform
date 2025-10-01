# Bootstrap Checklist for Azure AKS GitOps Platform

This checklist ensures you complete all necessary steps to avoid the "chicken and egg" problem with Terraform state backends and provider dependencies.

## Overview

The Azure AKS GitOps Platform requires a specific bootstrap sequence because:

1. **Terraform needs** → Storage account for state backend
2. **Storage account creation needs** → Service principal with permissions  
3. **Service principal needs** → Azure subscription access
4. **GitHub Actions needs** → All of the above configured
5. **cert-manager module needs** → kubectl and http providers declared

## Pre-Bootstrap Requirements

### Azure Account Setup
- [ ] Azure subscription with appropriate permissions
- [ ] Azure CLI installed and updated (`az --version`)
- [ ] Authenticated with Azure (`az login`)
- [ ] Correct subscription selected (`az account set --subscription "your-subscription-id"`)

### Development Environment
- [ ] Python 3.7+ installed (`python3 --version`)
- [ ] Git installed and configured
- [ ] GitHub CLI installed (optional but recommended)
- [ ] Terraform >= 1.0 installed (`terraform --version`)

### Repository Setup
- [ ] Repository cloned locally
- [ ] Working directory is project root
- [ ] No existing `.terraform/` directories in terraform folder

## Bootstrap Sequence

### Step 1: Environment Setup

```bash
# Navigate to project directory
cd aks-platform

# Set up Python virtual environment
./scripts/setup-python-env.sh
source venv/bin/activate

# Verify environment
python3 scripts/check-python-env.py
```

**Checklist:**
- [ ] Virtual environment created successfully
- [ ] Virtual environment activated (`echo $VIRTUAL_ENV`)
- [ ] Required Python packages installed
- [ ] No dependency conflicts reported

### Step 2: Azure Infrastructure Bootstrap

```bash
# Ensure Azure authentication
az login
az account set --subscription "your-subscription-id"

# Create foundational infrastructure
./scripts/setup-azure-credentials.sh --project-name "aks-platform" --location "East US"
```

**What this creates:**
- [ ] Resource group for Terraform state storage
- [ ] Storage account for Terraform state backend
- [ ] Blob container for state files
- [ ] Service principal for Terraform operations
- [ ] Service principal for GitHub Actions
- [ ] Backend configuration files (`backend.conf`)
- [ ] Environment variable files (`terraform.tfvars`)

**Checklist:**
- [ ] Script completed without errors
- [ ] Service principal credentials displayed (save securely)
- [ ] Backend configuration files generated
- [ ] Storage account accessible via Azure CLI

### Step 3: Provider Configuration Validation

The platform requires specific Terraform providers that must be declared correctly:

**Required providers in `terraform/terraform.tf`:**
- [ ] `azurerm` (hashicorp/azurerm)
- [ ] `azuread` (hashicorp/azuread)
- [ ] `kubernetes` (hashicorp/kubernetes)
- [ ] `helm` (hashicorp/helm)
- [ ] `kubectl` (gavinbunney/kubectl) **Critical: Must use gavinbunney, not hashicorp**
- [ ] `http` (hashicorp/http)
- [ ] `random` (hashicorp/random)
- [ ] `tls` (hashicorp/tls)

**Validation:**
```bash
# Check provider configuration
grep -A 20 "required_providers" terraform/terraform.tf
```

### Step 4: GitHub Integration (Optional but Recommended)

```bash
# Authenticate with GitHub
gh auth login

# Configure repository secrets
./scripts/setup-github-secrets.sh
```

**Checklist:**
- [ ] GitHub CLI authenticated
- [ ] Repository secrets configured:
  - [ ] `ARM_CLIENT_ID`
  - [ ] `ARM_CLIENT_SECRET`
  - [ ] `ARM_SUBSCRIPTION_ID`
  - [ ] `ARM_TENANT_ID`
  - [ ] `AZURE_CREDENTIALS`

### Step 5: Bootstrap Validation

```bash
# Comprehensive validation
./scripts/validate-bootstrap.sh --project-name "aks-platform" --environment dev
```

**Validation checks:**
- [ ] All prerequisites installed and configured
- [ ] Backend configuration valid and accessible
- [ ] Terraform variables properly set
- [ ] Azure resources exist and accessible
- [ ] Terraform providers correctly configured
- [ ] Terraform initialization successful

### Step 6: Commit and Deploy

```bash
# Add generated configuration files
git add terraform/environments/*/backend.conf
git add terraform/environments/*/terraform.tfvars

# Commit bootstrap configuration
git commit -m "feat: add Azure backend configuration and environment variables

- Add Terraform state backend configuration
- Add environment-specific variables
- Complete bootstrap process for greenfield deployment"

# Push to trigger deployment
git push origin main
```

**Checklist:**
- [ ] Configuration files committed
- [ ] Push successful
- [ ] GitHub Actions workflow triggered
- [ ] No immediate workflow failures

## Validation Commands

### Quick Health Check
```bash
# Check Azure authentication
az account show

# Check storage account
az storage account show --name $(grep storage_account_name terraform/environments/dev/backend.conf | cut -d'=' -f2 | tr -d ' "') --resource-group $(grep resource_group_name terraform/environments/dev/backend.conf | cut -d'=' -f2 | tr -d ' "')

# Test Terraform initialization
cd terraform && terraform init -backend-config="environments/dev/backend.conf"
```

### Comprehensive Validation
```bash
# Run full bootstrap validation
./scripts/validate-bootstrap.sh

# Check Python environment
python3 scripts/check-python-env.py

# Verify GitHub Actions status
gh run list --limit 5
```

## Common Issues and Solutions

### Issue: "Storage Account Not Found"
**Symptoms:** Terraform init fails with storage account not found error
**Solution:** Run bootstrap script: `./scripts/setup-azure-credentials.sh`

### Issue: "kubectl provider not found"
**Symptoms:** `Error: Failed to query available provider packages for hashicorp/kubectl`
**Solution:** Ensure `terraform.tf` uses `gavinbunney/kubectl` not `hashicorp/kubectl`

### Issue: "terraform.tfvars does not exist" in GitHub Actions
**Symptoms:**
```
Error: Failed to read variables file
Given variables file environments/dev/terraform.tfvars does not exist.
```
**Solution:** This was fixed in commit `f09f9db`. The GitHub Actions workflow now uses TF_VAR_ environment variables instead of committed tfvars files for security.

**Why this happens**:
- `*.tfvars` files are intentionally excluded from git (see `.gitignore`)
- Local development uses `terraform.tfvars` files (not committed)
- CI/CD uses `TF_VAR_` environment variables (secure)

### Issue: Multiple Workflow Runs
**Symptoms:** Two GitHub Actions runs on same commit
**Solution:** Workflow now includes concurrency control to prevent this

### Issue: Permission Denied
**Symptoms:** Azure operations fail with permission errors
**Solution:** Ensure your Azure account has Contributor role on subscription

### Issue: Virtual Environment Issues
**Symptoms:** Python package conflicts or import errors
**Solution:** Recreate virtual environment: `./scripts/setup-python-env.sh --force`

### Issue: Terraform Dependency Cycle Error
**Symptoms:**
```
Error: Cycle: module.aks.azurerm_role_assignment.aks_acr_pull, module.aks.azurerm_kubernetes_cluster.main
```
**Solution:** This was fixed in commit `1e591f6`. The AKS cluster no longer has a circular dependency with the ACR role assignment.

**Why this happens**: The role assignment depends on the kubelet identity from the AKS cluster, so it cannot be a dependency of the cluster itself.

### Issue: Multiple Workflows Running on Same Commit
**Symptoms:** Both Terraform Deploy and cost-monitoring workflows run on push events
**Solution:** This was fixed in commit `f86c830`. Cost-monitoring workflow now only runs on schedule or manual dispatch.

### Issue: "Unsupported block type" - quarantine_policy
**Symptoms:**
```
Error: Unsupported block type
on modules/container_registry/main.tf line 69, in resource "azurerm_container_registry" "main":
69: quarantine_policy {
Blocks of type "quarantine_policy" are not expected here.
```
**Solution:** This was fixed in commit `9c1a50c`. The deprecated `quarantine_policy` block was removed from the container registry module.

**Why this happens:** The `quarantine_policy` feature was deprecated and removed in Azure provider v3.x. Vulnerability scanning is now handled through Azure Security Center/Defender.

### Issue: "Unsupported argument" - Spot instance config in default node pool
**Symptoms:**
```
Error: Unsupported argument
on modules/aks/main.tf line 28: priority = var.enable_spot_instances ? "Spot" : "Regular"
An argument named "priority" is not expected here.
```
**Solution:** This was fixed in commit `eedd0ee`. Removed spot instance configuration from the default node pool.

**Why this happens:** The default node pool in AKS cannot use spot instances as it runs critical system components that require guaranteed availability. Spot instances should only be configured in additional user node pools.

## Post-Bootstrap Verification

After successful bootstrap, verify:

1. **GitHub Actions Status**
   ```bash
   gh run list --limit 3
   ```

2. **Azure Resources**
   ```bash
   az resource list --query "[?contains(resourceGroup, 'aks-platform')]" -o table
   ```

3. **Terraform State**
   ```bash
   cd terraform && terraform show
   ```

4. **AKS Cluster (after deployment)**
   ```bash
   az aks get-credentials --resource-group rg-aks-platform-dev --name aks-aks-platform-dev
   kubectl get nodes
   ```

## Success Criteria

Bootstrap is complete when:
- [ ] All validation checks pass
- [ ] Terraform can initialize without errors
- [ ] GitHub Actions workflow runs successfully
- [ ] Azure resources are created as expected
- [ ] No "chicken and egg" dependency issues

## Additional Resources

- [Scripts README](../scripts/README.md) - Detailed script documentation
- [Troubleshooting Guide](troubleshooting.md) - Common issues and solutions
- [Architecture Guide](architecture.md) - Understanding the platform design
- [Security Guide](security.md) - Security best practices

## Cleanup and Retry

If bootstrap fails and you need to start over:

```bash
# Clean up failed bootstrap
./scripts/cleanup-infrastructure.sh --project-name "aks-platform" --yes

# Remove local Terraform state
rm -rf terraform/.terraform*
rm -f terraform/environments/*/backend.conf
rm -f terraform/environments/*/terraform.tfvars

# Start bootstrap process again
./scripts/setup-azure-credentials.sh --project-name "aks-platform"
```

Remember: Bootstrap is a one-time process. Once completed successfully, normal Terraform workflows can be used for updates and changes.
