# AKS Cluster Upgrade Guide

This guide provides comprehensive procedures for upgrading Azure Kubernetes Service (AKS) clusters, including Kubernetes version upgrades, node pool upgrades, and node image updates.

## Quick Reference

### Available Scripts

| Script | Purpose | Usage |
|--------|---------|-------|
| `aks-upgrade-preflight.sh` | Pre-upgrade validation | `./scripts/aks-upgrade-preflight.sh -e dev -v 1.29.0` |
| `aks-upgrade-execute.sh` | Execute the upgrade | `./scripts/aks-upgrade-execute.sh -e dev -v 1.29.0 -m terraform` |
| `aks-upgrade-monitor.sh` | Real-time monitoring | `./scripts/aks-upgrade-monitor.sh -e dev` |
| `aks-upgrade-validate.sh` | Post-upgrade validation | `./scripts/aks-upgrade-validate.sh -e dev` |

### Quick Upgrade Workflow

```bash
# 1. Pre-flight checks
./scripts/aks-upgrade-preflight.sh --environment dev --target-version 1.29.0

# 2. Execute upgrade (Terraform method)
./scripts/aks-upgrade-execute.sh --environment dev --target-version 1.29.0 --method terraform

# 3. Monitor progress (in separate terminal)
./scripts/aks-upgrade-monitor.sh --environment dev

# 4. Validate after completion
./scripts/aks-upgrade-validate.sh --environment dev --extended
```

### Current Configuration

Upgrade settings are configured in `terraform/environments/<env>/terraform.tfvars`:

```hcl
# Node pool upgrade surge settings
system_node_pool_max_surge = "10%"   # Conservative for system workloads
user_node_pool_max_surge   = "33%"   # Standard for applications
ai_node_pool_max_surge     = "33%"   # Standard for AI workloads
```

## Table of Contents

1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Upgrade Types](#upgrade-types)
4. [Pre-Upgrade Checklist](#pre-upgrade-checklist)
5. [Upgrade Process](#upgrade-process)
6. [Upgrade Scripts Reference](#upgrade-scripts-reference)
7. [Rollback Procedures](#rollback-procedures)
8. [Troubleshooting](#troubleshooting)
9. [Best Practices](#best-practices)

## Overview

### AKS Upgrade Components

AKS upgrades involve three distinct components:

| Component | Description | Impact |
|-----------|-------------|--------|
| **Control Plane** | Kubernetes API server, etcd, controller-manager | Brief API unavailability during upgrade |
| **Node Pools** | Worker nodes running workloads | Rolling update, pods rescheduled |
| **Node Images** | OS and container runtime updates | Rolling update, minimal disruption |

### Upgrade Support Matrix

Azure supports N-2 Kubernetes version upgrades:
- Current version: 1.28.x
- Upgradable to: 1.29.x, 1.30.x (when available)
- Maximum skip: Cannot skip minor versions

### Environment Progression

All upgrades MUST follow this progression:

```
Development --> Staging --> Production
   (Day 1)      (Day 3)     (Day 7+)
```

## Prerequisites

### Required Tools

```bash
# Azure CLI (version 2.50.0+)
az --version

# kubectl (matching cluster version)
kubectl version --client

# Terraform (1.5.0+)
terraform --version

# jq for JSON processing
jq --version
```

### Required Permissions

- `Azure Kubernetes Service Contributor` role on the AKS cluster
- `Contributor` role on the node pool resource group
- Access to Terraform state backend

### Validation Script

Run the pre-upgrade validation before any upgrade:

```bash
./scripts/aks-upgrade-preflight.sh --environment <env> --target-version <version>
```

## Upgrade Types

### 1. Kubernetes Version Upgrade

Full cluster upgrade including control plane and all node pools.

**When to use:**
- Security patches requiring new Kubernetes version
- New Kubernetes features needed
- Version approaching end-of-support

**Impact:**
- Control plane: 1-5 minutes API unavailability
- Node pools: Rolling update based on `max_surge` setting

### 2. Node Pool Upgrade

Upgrade specific node pools without changing the control plane.

**When to use:**
- Node pool version lags behind control plane
- Different upgrade schedules for different workload types

### 3. Node Image Update

Update the OS image on nodes without changing Kubernetes version.

**When to use:**
- Security patches for the node OS
- Container runtime updates
- Regular maintenance (recommended monthly)

## Pre-Upgrade Checklist

### 1. Version Compatibility Check

```bash
# Check available versions
az aks get-versions --location <location> --output table

# Check current cluster version
az aks show --resource-group <rg> --name <cluster> --query kubernetesVersion

# Check upgrade paths
az aks get-upgrades --resource-group <rg> --name <cluster> --output table
```

### 2. Cluster Health Check

```bash
# Run comprehensive health check
./scripts/aks-upgrade-preflight.sh --environment <env> --check-only

# Manual checks
kubectl get nodes
kubectl get pods --all-namespaces | grep -v Running
kubectl top nodes
```

### 3. Application Compatibility

Before upgrading, verify:

- [ ] All applications tested with target Kubernetes version
- [ ] Helm charts compatible with target version
- [ ] No deprecated APIs in use (use `kubectl deprecations` or Pluto)
- [ ] PodDisruptionBudgets configured for critical workloads
- [ ] Resource requests/limits set on all pods

```bash
# Check for deprecated APIs
kubectl get --raw /metrics | grep apiserver_requested_deprecated_apis

# Or use Pluto
pluto detect-all-in-cluster
```

### 4. Backup Verification

```bash
# Verify etcd backup exists (Azure manages this automatically)
az aks show --resource-group <rg> --name <cluster> --query "addonProfiles"

# Backup critical namespaces
kubectl get all,configmaps,secrets -n <namespace> -o yaml > backup-<namespace>.yaml

# Backup ArgoCD applications
kubectl get applications -n argocd -o yaml > backup-argocd-apps.yaml
```

### 5. Resource Capacity Check

Ensure sufficient capacity for surge nodes:

```bash
# Check current node count and limits
az aks nodepool list --resource-group <rg> --cluster-name <cluster> --output table

# Verify Azure quota for additional VMs
az vm list-usage --location <location> --output table | grep -i "Standard D"
```

## Upgrade Process

### Method 1: Terraform-Based Upgrade (Recommended)

This method ensures upgrades are tracked in infrastructure-as-code.

#### Step 1: Update Kubernetes Version in Terraform

Edit `terraform/variables.tf` or environment-specific tfvars:

```hcl
# terraform/environments/<env>/terraform.tfvars
kubernetes_version = "1.29.0"  # Target version
```

#### Step 2: Run Pre-Flight Checks

```bash
./scripts/aks-upgrade-preflight.sh \
  --environment <env> \
  --target-version "1.29.0"
```

#### Step 3: Apply Terraform Changes

```bash
cd terraform

# Initialize
terraform init -backend-config="environments/<env>/backend.conf"

# Plan the upgrade
terraform plan \
  -var-file="environments/<env>/terraform.tfvars" \
  -out="upgrade-<env>.tfplan"

# Review the plan carefully
terraform show "upgrade-<env>.tfplan"

# Apply when ready
terraform apply "upgrade-<env>.tfplan"
```

#### Step 4: Monitor Upgrade Progress

```bash
# Watch node pool upgrade
watch -n 5 'kubectl get nodes -o wide'

# Monitor in another terminal
./scripts/aks-upgrade-monitor.sh --environment <env>
```

#### Step 5: Post-Upgrade Validation

```bash
./scripts/aks-upgrade-validate.sh --environment <env>
```

### Method 2: Azure CLI Upgrade

For urgent upgrades outside the normal Terraform workflow.

#### Control Plane Upgrade

```bash
# Upgrade control plane only
az aks upgrade \
  --resource-group "rg-aks-platform-<env>" \
  --name "aks-aks-platform-<env>" \
  --kubernetes-version "1.29.0" \
  --control-plane-only \
  --yes
```

#### Node Pool Upgrade

```bash
# Upgrade specific node pool
az aks nodepool upgrade \
  --resource-group "rg-aks-platform-<env>" \
  --cluster-name "aks-aks-platform-<env>" \
  --name "system" \
  --kubernetes-version "1.29.0" \
  --max-surge "10%"
```

#### Full Cluster Upgrade

```bash
# Upgrade control plane and all node pools
az aks upgrade \
  --resource-group "rg-aks-platform-<env>" \
  --name "aks-aks-platform-<env>" \
  --kubernetes-version "1.29.0" \
  --yes
```

**Important:** After CLI upgrades, sync Terraform state:

```bash
terraform import azurerm_kubernetes_cluster.main <resource_id>
# Or update tfvars to match and run terraform apply
```

### Method 3: Node Image Update Only

```bash
# Update node images without version change
az aks nodepool upgrade \
  --resource-group "rg-aks-platform-<env>" \
  --cluster-name "aks-aks-platform-<env>" \
  --name "system" \
  --node-image-only
```

## Upgrade Scripts Reference

### Script Overview

| Script | Purpose | When to Use |
|--------|---------|-------------|
| `aks-upgrade-preflight.sh` | Pre-upgrade validation | Before every upgrade |
| `aks-upgrade-execute.sh` | Execute the upgrade | Primary upgrade tool |
| `aks-upgrade-monitor.sh` | Real-time monitoring | During upgrade |
| `aks-upgrade-validate.sh` | Post-upgrade validation | After upgrade completes |

### aks-upgrade-preflight.sh

Performs comprehensive validation before upgrades.

**Checks Performed:**
- Prerequisites (Azure CLI, kubectl, jq)
- Cluster connectivity
- Version compatibility and upgrade path
- Node pool health
- Node status and conditions
- Pod health and problem pods
- PodDisruptionBudgets
- Deprecated API usage
- Resource capacity for surge nodes
- Critical service health (ArgoCD, Monitoring, CoreDNS)

**Usage:**
```bash
# Full pre-flight check
./scripts/aks-upgrade-preflight.sh --environment dev --target-version 1.29.0

# Health check only (no version specified)
./scripts/aks-upgrade-preflight.sh --environment prod --check-only

# With verbose output
./scripts/aks-upgrade-preflight.sh -e staging -v 1.29.0 --verbose
```

**Options:**
| Option | Description |
|--------|-------------|
| `--environment, -e` | Target environment (required) |
| `--target-version, -v` | Target Kubernetes version |
| `--project-name, -p` | Project name (default: aks-platform) |
| `--check-only` | Run health checks only |
| `--verbose` | Show detailed output |

### aks-upgrade-execute.sh

Executes the upgrade with safety mechanisms.

**Features:**
- Pre-flight checks before upgrade
- Terraform state backup
- Progress monitoring
- Post-upgrade validation
- Dry-run mode for testing

**Usage:**
```bash
# Terraform-based upgrade (recommended)
./scripts/aks-upgrade-execute.sh --environment dev --target-version 1.29.0 --method terraform

# Azure CLI upgrade
./scripts/aks-upgrade-execute.sh --environment staging --target-version 1.29.0 --method cli

# Control plane only
./scripts/aks-upgrade-execute.sh -e prod -v 1.29.0 -m cli --control-plane-only

# Specific node pool
./scripts/aks-upgrade-execute.sh -e dev -v 1.29.0 -m cli --node-pool user

# Node image update only
./scripts/aks-upgrade-execute.sh --environment prod --node-image-only

# Dry run
./scripts/aks-upgrade-execute.sh -e prod -v 1.29.0 --dry-run
```

**Options:**
| Option | Description |
|--------|-------------|
| `--environment, -e` | Target environment (required) |
| `--target-version, -v` | Target Kubernetes version |
| `--method, -m` | Upgrade method: terraform or cli |
| `--node-pool` | Upgrade specific node pool only |
| `--node-image-only` | Update node images without version change |
| `--control-plane-only` | Upgrade control plane only (CLI method) |
| `--skip-preflight` | Skip pre-flight checks |
| `--skip-validation` | Skip post-upgrade validation |
| `--no-backup` | Skip Terraform state backup |
| `--dry-run` | Show what would happen without making changes |

### aks-upgrade-monitor.sh

Provides real-time monitoring during upgrades.

**Displays:**
- Cluster provisioning state
- Node pool status and versions
- Node status (Ready/NotReady)
- System pod health
- Upgrade progress indicators
- Recent cluster events

**Usage:**
```bash
# Start monitoring
./scripts/aks-upgrade-monitor.sh --environment dev

# Custom refresh interval
./scripts/aks-upgrade-monitor.sh -e prod --interval 60

# Limit monitoring duration
./scripts/aks-upgrade-monitor.sh -e staging --max-duration 3600
```

**Options:**
| Option | Description |
|--------|-------------|
| `--environment, -e` | Target environment (required) |
| `--interval, -i` | Refresh interval in seconds (default: 30) |
| `--max-duration` | Max monitoring time in seconds (default: 7200) |

### aks-upgrade-validate.sh

Validates cluster health after upgrade completion.

**Checks Performed:**
- Cluster version verification
- Node health and conditions
- System pod status
- Workload status (Deployments, StatefulSets, DaemonSets)
- Platform services (ArgoCD, Monitoring, AI Tools)
- Extended checks (DNS, PVCs, Ingress, Certificates)

**Usage:**
```bash
# Basic validation
./scripts/aks-upgrade-validate.sh --environment dev

# Extended validation
./scripts/aks-upgrade-validate.sh --environment prod --extended

# Output results to JSON
./scripts/aks-upgrade-validate.sh -e staging -o validation-results.json
```

**Options:**
| Option | Description |
|--------|-------------|
| `--environment, -e` | Target environment (required) |
| `--extended` | Run extended validation checks |
| `--output, -o` | Write results to JSON file |
| `--verbose` | Show detailed output |

### Complete Upgrade Workflow Example

```bash
# ============================================
# Development Environment Upgrade
# ============================================

# Step 1: Pre-flight checks
./scripts/aks-upgrade-preflight.sh \
  --environment dev \
  --target-version 1.29.0

# Step 2: Execute upgrade (in one terminal)
./scripts/aks-upgrade-execute.sh \
  --environment dev \
  --target-version 1.29.0 \
  --method terraform

# Step 3: Monitor progress (in another terminal)
./scripts/aks-upgrade-monitor.sh --environment dev

# Step 4: Validate after completion
./scripts/aks-upgrade-validate.sh \
  --environment dev \
  --extended

# ============================================
# After 2-3 days, repeat for Staging
# ============================================

# ============================================
# After 7+ days, repeat for Production
# (with additional caution)
# ============================================

# Production dry-run first
./scripts/aks-upgrade-execute.sh \
  --environment prod \
  --target-version 1.29.0 \
  --dry-run

# Then actual upgrade during maintenance window
./scripts/aks-upgrade-execute.sh \
  --environment prod \
  --target-version 1.29.0 \
  --method terraform
```

## Rollback Procedures

### Rollback Limitations

**Important:** Kubernetes version rollback is NOT supported by Azure. Once upgraded, you cannot downgrade the control plane version.

### Recovery Options

#### Option 1: Restore from Backup (Full Recovery)

If the upgrade causes critical issues:

1. Create a new cluster with the previous version
2. Restore applications and data from backups
3. Update DNS/load balancer to point to new cluster

```bash
# Create new cluster with previous version
terraform workspace new recovery
terraform apply -var "kubernetes_version=1.28.5"
```

#### Option 2: Node Pool Recreation

If only node pools are affected:

```bash
# Delete and recreate node pool with previous version
az aks nodepool delete \
  --resource-group <rg> \
  --cluster-name <cluster> \
  --name user \
  --yes

az aks nodepool add \
  --resource-group <rg> \
  --cluster-name <cluster> \
  --name user \
  --kubernetes-version <previous-version> \
  --node-count 3
```

#### Option 3: Application Rollback

If applications fail after upgrade:

```bash
# Rollback ArgoCD applications
kubectl patch application <app-name> -n argocd \
  --type merge \
  -p '{"operation":{"sync":{"revision":"<previous-revision>"}}}'

# Or use Helm rollback
helm rollback <release> <revision> -n <namespace>
```

## Troubleshooting

### Common Issues

#### 1. Upgrade Stuck

```bash
# Check node pool operation status
az aks nodepool show \
  --resource-group <rg> \
  --cluster-name <cluster> \
  --name <nodepool> \
  --query provisioningState

# Check for failed nodes
kubectl get nodes | grep -v Ready
kubectl describe node <node-name>
```

#### 2. Pods Not Rescheduling

```bash
# Check PodDisruptionBudgets
kubectl get pdb --all-namespaces

# Check for pods blocking drain
kubectl get pods --field-selector=status.phase!=Running --all-namespaces
```

#### 3. Quota Exceeded

```bash
# Check Azure quota
az vm list-usage --location <location> --output table

# Request quota increase through Azure portal
```

#### 4. Node Image Pull Failures

```bash
# Check ACR connectivity
az aks check-acr --resource-group <rg> --name <cluster> --acr <acr-name>

# Verify node can reach ACR
kubectl run test --image=<acr>.azurecr.io/test --rm -it --restart=Never
```

### Diagnostic Commands

```bash
# Cluster events
kubectl get events --sort-by='.lastTimestamp' -A

# Node conditions
kubectl get nodes -o custom-columns=NAME:.metadata.name,CONDITIONS:.status.conditions[*].type

# API server logs (if accessible)
az aks logs --resource-group <rg> --name <cluster>

# Kubelet logs on a node
kubectl debug node/<node-name> -it --image=busybox -- cat /var/log/kubelet.log
```

## Best Practices

### Scheduling

- **Development:** Upgrade immediately when new version available
- **Staging:** 2-3 days after successful dev upgrade
- **Production:** 7+ days after staging, during maintenance window

### Communication

1. Announce planned upgrade 1 week in advance
2. Notify stakeholders 24 hours before production upgrade
3. Send completion notice after successful upgrade

### Monitoring During Upgrade

Monitor these metrics during upgrade:

- API server latency
- Node readiness
- Pod restart count
- Application error rates
- Deployment availability

```bash
# Watch key metrics
kubectl get --raw /metrics | grep -E "apiserver_request_duration|node_ready"
```

### Automation

- Use GitHub Actions for automated dev/staging upgrades
- Require manual approval for production upgrades
- Implement automated rollback triggers

### Documentation

After each upgrade:

1. Document actual upgrade duration
2. Note any issues encountered
3. Update runbooks if needed
4. Archive upgrade logs

## Related Documentation

- [Production Update Strategy](./production-update-strategy.md)
- [Troubleshooting Guide](./troubleshooting.md)
- [Deployment Guide](./deployment-guide.md)
- [Microsoft AKS Upgrade Documentation](https://learn.microsoft.com/en-us/azure/aks/upgrade-cluster)

## Appendix: Version Support Schedule

| Kubernetes Version | AKS GA Date | End of Support |
|-------------------|-------------|----------------|
| 1.28.x | 2023-12 | 2024-12 |
| 1.29.x | 2024-03 | 2025-03 |
| 1.30.x | 2024-06 | 2025-06 |

Check current support status:
```bash
az aks get-versions --location <location> --output table
```
