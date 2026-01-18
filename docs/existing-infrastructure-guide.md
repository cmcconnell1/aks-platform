# Existing Infrastructure Integration Guide

This guide explains how to adapt the Terraform configuration for existing Azure environments.

## Use Case 1: Greenfield New Azure Tenant

**Status**: Use as-is - Perfect fit

The Terraform creates everything needed from scratch with no conflicts.

```bash
# Deploy directly
./scripts/setup-azure-credentials.sh
terraform apply -var-file=environments/dev/terraform.tfvars
```

## Use Case 2: Existing Tenant with Other AKS Clusters

**Status**: Requires customization - Use different IP ranges and resource names.

### Potential Conflicts
- IP address ranges overlapping with existing VNets
- Resource naming conflicts
- Regional placement considerations
- DNS zone conflicts

### Solution: Customize Variables

When deploying to an existing Azure tenant that already has other AKS clusters, you need to ensure no conflicts with existing resources.

#### Basic Configuration Example

```hcl
# terraform/environments/existing-tenant/terraform.tfvars
project_name = "aks-platform-new"
vnet_address_space = ["10.1.0.0/16"]  # Different IP range
location = "West US 2"  # Different region if needed

# Subnet configurations with non-overlapping ranges
aks_subnet_address_prefix = "10.1.1.0/24"
agc_subnet_address_prefix = "10.1.2.0/24"
private_endpoint_subnet_address_prefix = "10.1.3.0/24"
database_subnet_address_prefix = "10.1.4.0/24"

# Different SSL certificate
ssl_certificate_subject = "aks-new.company.com"
ssl_certificate_dns_names = ["aks-new.company.com", "*.aks-new.company.com"]
```

#### IP Range Planning

Before deployment, check existing VNet ranges in your subscription:

```bash
# List existing VNets and their address spaces
az network vnet list --query "[].{Name:name, AddressSpace:addressSpace.addressPrefixes}" -o table

# Check for conflicts with your planned range
az network vnet list --query "[?contains(addressSpace.addressPrefixes, '10.1.0.0/16')]"
```

#### Resource Naming Strategy

Use a consistent naming convention to avoid conflicts:

```hcl
# Example naming strategy
project_name = "aks-platform-prod"  # or "aks-platform-team-a"
environment = "prod"              # or "dev", "staging"

# This will create resources like:
# - rg-aks-platform-prod-eastus
# - aks-aks-platform-prod-eastus
# - alb-aks-platform-prod-eastus (AGC)
```

## Use Case 3: Existing Tenant - Existing AKS Integration

**Status**: Requires Terraform modifications

### Option A: Platform Services Only

Create a modified main.tf that skips infrastructure and only deploys platform services:

```hcl
# terraform/existing-aks/main.tf
data "azurerm_kubernetes_cluster" "existing" {
  name                = var.existing_aks_cluster_name
  resource_group_name = var.existing_aks_resource_group
}

data "azurerm_resource_group" "existing" {
  name = var.existing_aks_resource_group
}

# Skip: Resource Group, Networking, AKS modules
# Deploy only: GitOps, AI Tools, Monitoring modules

module "gitops" {
  source = "../modules/gitops"
  count  = var.enable_argocd ? 1 : 0

  argocd_namespace = var.argocd_namespace
  argocd_domain    = "argocd.${var.ssl_certificate_subject}"
  enable_ingress   = var.enable_agc
}

module "ai_tools" {
  source = "../modules/ai_tools"
  count  = var.enable_ai_tools ? 1 : 0
  
  enable_jupyter_hub = var.enable_jupyter_hub
  enable_mlflow      = var.enable_mlflow
  enable_kubeflow    = var.enable_kubeflow
  enable_gpu_support = var.enable_ai_node_pool
}

module "monitoring" {
  source = "../modules/monitoring"
  count  = var.enable_monitoring ? 1 : 0

  enable_grafana_ingress = var.enable_agc
  grafana_ingress_hosts  = ["grafana.${var.ssl_certificate_subject}"]
}
```

### Option B: Use Existing Networking

Modify the main.tf to use existing VNet:

```hcl
# Data sources for existing infrastructure
data "azurerm_virtual_network" "existing" {
  name                = var.existing_vnet_name
  resource_group_name = var.existing_network_resource_group
}

data "azurerm_subnet" "existing_aks" {
  name                 = var.existing_aks_subnet_name
  virtual_network_name = data.azurerm_virtual_network.existing.name
  resource_group_name  = var.existing_network_resource_group
}

# Skip networking module, use existing
# Modify AKS module to use existing subnet
module "aks" {
  source = "./modules/aks"
  
  vnet_subnet_id = data.azurerm_subnet.existing_aks.id
  # ... other configuration
}
```

## Implementation Steps for Existing Infrastructure

### Step 1: Assess Current Environment

```bash
# List existing AKS clusters
az aks list --output table

# List existing VNets
az network vnet list --output table

# Check IP ranges
az network vnet show --name existing-vnet --resource-group existing-rg --query addressSpace
```

### Step 2: Choose Integration Approach

**New Cluster (Recommended)**:
- Minimal conflicts
- Clean separation
- Easy rollback

**Platform Services Only**:
- No infrastructure changes
- Quick deployment
- Limited to software components

**Full Integration**:
- Maximum customization required
- Potential for conflicts
- Requires Terraform expertise

### Step 3: Create Custom Configuration

```bash
# Create custom environment
mkdir terraform/environments/existing-integration
cp terraform/environments/dev/terraform.tfvars.example \
   terraform/environments/existing-integration/terraform.tfvars

# Customize for your environment
vim terraform/environments/existing-integration/terraform.tfvars
```

### Step 4: Validate Before Apply

```bash
# Always plan first
terraform plan -var-file=environments/existing-integration/terraform.tfvars

# Check for conflicts
terraform plan -detailed-exitcode
```

## Variables for Existing Infrastructure

### Required Variables for Integration

```hcl
# Existing infrastructure references
existing_aks_cluster_name = "my-existing-aks"
existing_aks_resource_group = "my-aks-rg"
existing_vnet_name = "my-existing-vnet"
existing_network_resource_group = "my-network-rg"
existing_aks_subnet_name = "aks-subnet"

# New resource configuration
project_name = "aks-platform-integration"
location = "East US"  # Should match existing resources

# Disable conflicting components
enable_agc = false  # If you have existing ingress
create_demo_ssl_certificate = false  # If you have existing certs
```

## Migration Strategies

### Gradual Migration

1. **Phase 1**: Deploy platform services only
2. **Phase 2**: Migrate applications to ArgoCD
3. **Phase 3**: Implement monitoring and AI tools
4. **Phase 4**: Consider infrastructure consolidation

### Blue-Green Approach

1. Deploy complete new environment
2. Migrate applications gradually
3. Switch traffic using DNS/load balancer
4. Decommission old environment

## Troubleshooting Common Issues

### IP Range Conflicts
```bash
# Check existing IP ranges
az network vnet list --query "[].{Name:name, AddressSpace:addressSpace}" --output table

# Use non-overlapping ranges
vnet_address_space = ["10.2.0.0/16"]  # Different from existing 10.0.0.0/16
```

### Resource Naming Conflicts
```bash
# Use unique project names
project_name = "aks-platform-$(date +%Y%m%d)"
```

### Permission Issues
```bash
# Ensure service principal has access to existing resources
az role assignment create \
  --assignee $ARM_CLIENT_IP \
  --role "Network Contributor" \
  --scope "/subscriptions/$ARM_SUBSCRIPTION_ID/resourceGroups/existing-network-rg"
```

## Best Practices for Existing Environments

1. **Start Small**: Deploy platform services first
2. **Test Thoroughly**: Use dev/staging environments
3. **Plan Rollback**: Have a rollback strategy
4. **Document Changes**: Keep track of modifications
5. **Gradual Migration**: Don't migrate everything at once
6. **Monitor Impact**: Watch for performance/cost changes
7. **Backup First**: Backup existing configurations

## Support

For complex existing environment integrations, consider:
- Creating a custom branch for your modifications
- Testing in a separate subscription first
- Engaging Azure support for architecture review
- Using Azure Migrate for assessment
