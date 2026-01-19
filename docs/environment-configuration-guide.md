# Environment Configuration Guide

This guide documents the environment-specific configuration approach for the Azure AKS GitOps Platform, including all configurable variables, environment differences, and best practices.

## Table of Contents

1. [Configuration Philosophy](#configuration-philosophy)
2. [Directory Structure](#directory-structure)
3. [Environment Comparison](#environment-comparison)
4. [Variable Reference](#variable-reference)
5. [Sensitive Credentials](#sensitive-credentials)
6. [Backend Configuration](#backend-configuration)
7. [Customization Guide](#customization-guide)
8. [Best Practices](#best-practices)

## Configuration Philosophy

This platform follows Terraform best practices for environment management:

### Principles

1. **DRY (Don't Repeat Yourself)**: Base infrastructure defined in modules, environment-specific values in tfvars
2. **Environment Parity**: Same code across all environments, only configurations differ
3. **Explicit Configuration**: No magic defaults for critical settings
4. **Security First**: Sensitive values never committed to version control
5. **Auditability**: Clear documentation of what differs between environments

### What Goes Where

| Configuration Type | Location | Example |
|-------------------|----------|---------|
| Infrastructure Logic | `terraform/modules/` | Resource definitions, dependencies |
| Variable Definitions | `terraform/variables.tf` | Variable types, descriptions, defaults |
| Environment Values | `terraform/environments/<env>/terraform.tfvars` | Actual values for each environment |
| Backend Config | `terraform/environments/<env>/backend.conf` | State storage location |
| Sensitive Values | Environment variables | Passwords, secrets |

## Directory Structure

```
terraform/
├── main.tf                          # Root module - orchestrates all modules
├── variables.tf                     # Variable definitions with defaults
├── outputs.tf                       # Output values
├── terraform.tf                     # Provider configurations
├── environments/
│   ├── dev/
│   │   ├── terraform.tfvars        # Development environment values
│   │   └── backend.conf            # Dev state backend config
│   ├── staging/
│   │   ├── terraform.tfvars        # Staging environment values
│   │   └── backend.conf            # Staging state backend config
│   └── prod/
│       ├── terraform.tfvars        # Production environment values
│       └── backend.conf            # Prod state backend config
└── modules/
    ├── aks/                        # AKS cluster module
    ├── agc/                        # Application Gateway for Containers
    ├── networking/                 # Virtual network module
    ├── security/                   # Key Vault, identities
    ├── container_registry/         # Azure Container Registry
    ├── cert_manager/               # Certificate management
    ├── monitoring/                 # Prometheus, Grafana
    ├── gitops/                     # ArgoCD
    └── ai_tools/                   # JupyterHub, MLflow
```

## Environment Comparison

### Compute Resources

| Setting | Dev | Staging | Prod | Notes |
|---------|-----|---------|------|-------|
| `aks_node_count` | 2 | 2 | 3 | Initial node count |
| `aks_min_node_count` | 1 | 2 | 3 | Minimum for autoscaling |
| `aks_max_node_count` | 5 | 8 | 15 | Maximum for autoscaling |
| `aks_node_vm_size` | Standard_D2s_v3 | Standard_D2s_v3 | Standard_D4s_v3 | VM SKU |
| `ai_node_count` | 1 | 1 | 2 | GPU nodes |

### Storage Configuration

| Setting | Dev | Staging | Prod | Notes |
|---------|-----|---------|------|-------|
| `prometheus_storage_size` | 30Gi | 50Gi | 100Gi | Metrics storage |
| `prometheus_retention` | 15d | 30d | 90d | Data retention |
| `grafana_storage_size` | 5Gi | 10Gi | 20Gi | Dashboard storage |
| `loki_storage_size` | 30Gi | 50Gi | 100Gi | Log storage |
| `system_node_pool_os_disk_size_gb` | 100 | 100 | 128 | System disk |

### Network Configuration

| Setting | Dev | Staging | Prod | Notes |
|---------|-----|---------|------|-------|
| `vnet_address_space` | 10.0.0.0/16 | 10.1.0.0/16 | 10.10.0.0/16 | Unique per env |
| `aks_subnet_address_prefix` | 10.0.1.0/24 | 10.1.1.0/24 | 10.10.1.0/24 | AKS nodes |
| `enable_private_cluster` | false | false | true | Private API server (prod only) |

### Security Configuration

| Setting | Dev | Staging | Prod | Notes |
|---------|-----|---------|------|-------|
| `create_demo_ssl_certificate` | true | true | false | Demo certs |
| `enable_cert_manager` | false | false | true | Let's Encrypt |
| `enable_letsencrypt_prod` | false | false | true | Production certs |
| `enable_agc` | true | true | true | AGC enabled |

### Upgrade Configuration

| Setting | Dev | Staging | Prod | Notes |
|---------|-----|---------|------|-------|
| `system_node_pool_max_surge` | 10% | 10% | 10% | Conservative for system |
| `user_node_pool_max_surge` | 33% | 33% | 25% | More conservative in prod |
| `ai_node_pool_max_surge` | 33% | 33% | 25% | GPU node upgrades |

## Variable Reference

### Core Configuration

```hcl
# Required
variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

# Optional with defaults
variable "location" {
  description = "Azure region for resources"
  type        = string
  default     = "East US"
}

variable "project_name" {
  description = "Name of the project (used in resource naming)"
  type        = string
  default     = "aks-platform"
}
```

### AKS Configuration

```hcl
variable "kubernetes_version" {
  description = "Kubernetes version for AKS cluster"
  type        = string
  default     = "1.29.0"
}

variable "aks_node_count" {
  description = "Initial number of nodes in the default node pool"
  type        = number
  default     = 2
}

variable "aks_node_vm_size" {
  description = "VM size for AKS nodes"
  type        = string
  default     = "Standard_D2s_v3"
}

variable "aks_max_node_count" {
  description = "Maximum number of nodes for autoscaling"
  type        = number
  default     = 10
}

variable "aks_min_node_count" {
  description = "Minimum number of nodes for autoscaling"
  type        = number
  default     = 1
}
```

### Network Configuration

```hcl
variable "vnet_address_space" {
  description = "Address space for the virtual network"
  type        = list(string)
  default     = ["10.0.0.0/16"]
}

variable "aks_service_cidr" {
  description = "CIDR for Kubernetes services"
  type        = string
  default     = "10.2.0.0/24"
}

variable "aks_dns_service_ip" {
  description = "IP address for Kubernetes DNS service"
  type        = string
  default     = "10.2.0.10"
}

variable "enable_private_cluster" {
  description = "Enable private AKS cluster"
  type        = bool
  default     = true
}
```

### Node Pool Configuration

```hcl
# Disk sizes
variable "system_node_pool_os_disk_size_gb" {
  description = "OS disk size in GB for system node pool"
  type        = number
  default     = 100
}

variable "user_node_pool_os_disk_size_gb" {
  description = "OS disk size in GB for user node pool"
  type        = number
  default     = 100
}

variable "ai_node_pool_os_disk_size_gb" {
  description = "OS disk size in GB for AI/ML node pool"
  type        = number
  default     = 200
}

# Upgrade settings
variable "system_node_pool_max_surge" {
  description = "Max surge for system node pool upgrades"
  type        = string
  default     = "10%"
}

variable "user_node_pool_max_surge" {
  description = "Max surge for user node pool upgrades"
  type        = string
  default     = "33%"
}
```

### Autoscaler Profile

```hcl
variable "aks_autoscaler_profile" {
  description = "Autoscaler profile configuration"
  type = object({
    balance_similar_node_groups      = optional(bool, false)
    expander                         = optional(string, "random")
    max_graceful_termination_sec     = optional(string, "600")
    max_node_provisioning_time       = optional(string, "15m")
    max_unready_nodes                = optional(number, 3)
    max_unready_percentage           = optional(number, 45)
    new_pod_scale_up_delay           = optional(string, "10s")
    scale_down_delay_after_add       = optional(string, "10m")
    scale_down_delay_after_delete    = optional(string, "10s")
    scale_down_delay_after_failure   = optional(string, "3m")
    scan_interval                    = optional(string, "10s")
    scale_down_unneeded              = optional(string, "10m")
    scale_down_unready               = optional(string, "20m")
    scale_down_utilization_threshold = optional(string, "0.5")
  })
  default = {}
}
```

### Monitoring Configuration

```hcl
variable "prometheus_storage_size" {
  description = "Storage size for Prometheus"
  type        = string
  default     = "50Gi"
}

variable "prometheus_retention" {
  description = "Data retention period for Prometheus"
  type        = string
  default     = "30d"
}

variable "grafana_storage_size" {
  description = "Storage size for Grafana"
  type        = string
  default     = "10Gi"
}

variable "loki_storage_size" {
  description = "Storage size for Loki log aggregation"
  type        = string
  default     = "50Gi"
}
```

### Helm Chart Versions

```hcl
variable "helm_chart_versions" {
  description = "Versions for Helm charts used in the platform"
  type = object({
    cert_manager     = optional(string, "v1.13.2")
    argocd           = optional(string, "5.51.6")
    prometheus_stack = optional(string, "55.5.0")
    loki             = optional(string, "2.9.11")
    promtail         = optional(string, "6.15.3")
    jaeger           = optional(string, "0.71.11")
    jupyterhub       = optional(string, "3.1.0")
    mlflow           = optional(string, "0.7.19")
  })
  default = {}
}
```

## Sensitive Credentials

### Required Credentials

The following credentials are **required** and have no defaults for security:

| Variable | Description | Used By |
|----------|-------------|---------|
| `grafana_admin_password` | Grafana admin password | Monitoring module |
| `mlflow_db_password` | MLflow PostgreSQL password | AI Tools module |
| `mlflow_minio_password` | MLflow MinIO password | AI Tools module |

### Providing Credentials

#### Option 1: Environment Variables (Recommended for CI/CD)

```bash
export TF_VAR_grafana_admin_password="your-secure-password"
export TF_VAR_mlflow_db_password="your-secure-password"
export TF_VAR_mlflow_minio_password="your-secure-password"

terraform apply -var-file=environments/dev/terraform.tfvars
```

#### Option 2: Separate Secrets File (Local Development)

Create a file `terraform/environments/<env>/secrets.tfvars`:

```hcl
# DO NOT COMMIT THIS FILE
grafana_admin_password = "your-secure-password"
mlflow_db_password     = "your-secure-password"
mlflow_minio_password  = "your-secure-password"
```

Apply with:
```bash
terraform apply \
  -var-file=environments/dev/terraform.tfvars \
  -var-file=environments/dev/secrets.tfvars
```

Add to `.gitignore`:
```
**/secrets.tfvars
```

#### Option 3: Azure Key Vault (Production)

For production, retrieve secrets from Azure Key Vault:

```bash
export TF_VAR_grafana_admin_password=$(az keyvault secret show \
  --vault-name "your-keyvault" \
  --name "grafana-admin-password" \
  --query value -o tsv)
```

### Password Requirements

- Minimum 12 characters
- Mix of uppercase, lowercase, numbers, and special characters
- No dictionary words
- Unique per environment

## Backend Configuration

### Structure

Each environment has its own `backend.conf`:

```hcl
# terraform/environments/<env>/backend.conf
resource_group_name  = "aks-platform-terraform-state-rg"
storage_account_name = "aksplatftf<env><random>"
container_name       = "tfstate"
key                  = "<env>/terraform.tfstate"
```

### Setting Up Backend Storage

```bash
# Create backend resources for each environment
./scripts/setup-azure-credentials.sh --environment dev
./scripts/setup-azure-credentials.sh --environment staging
./scripts/setup-azure-credentials.sh --environment prod
```

### State Isolation

Each environment uses:
- Same resource group (for management)
- Same storage account (different for security in prod)
- Different state file key

## Customization Guide

### Adding a New Variable

1. **Define in `terraform/variables.tf`**:
```hcl
variable "new_setting" {
  description = "Description of the setting"
  type        = string
  default     = "default-value"
}
```

2. **Add to each environment's tfvars**:
```hcl
# environments/dev/terraform.tfvars
new_setting = "dev-value"

# environments/staging/terraform.tfvars
new_setting = "staging-value"

# environments/prod/terraform.tfvars
new_setting = "prod-value"
```

3. **Use in module**:
```hcl
module "example" {
  new_setting = var.new_setting
}
```

### Adding a New Environment

1. Create directory:
```bash
mkdir -p terraform/environments/new-env
```

2. Copy from existing:
```bash
cp terraform/environments/dev/terraform.tfvars terraform/environments/new-env/
cp terraform/environments/dev/backend.conf terraform/environments/new-env/
```

3. Update values for new environment

4. Set up backend storage:
```bash
./scripts/setup-azure-credentials.sh --environment new-env
```

### Environment-Specific Overrides

For complex settings, use environment-specific object overrides:

```hcl
# Production-specific autoscaler tuning
aks_autoscaler_profile = {
  expander                    = "least-waste"
  scale_down_delay_after_add  = "15m"
  scale_down_unneeded         = "15m"
}
```

## Best Practices

### Configuration Management

1. **Version Pin Everything**: Pin Kubernetes and Helm chart versions explicitly
2. **Document Changes**: Update this guide when adding variables
3. **Review Before Apply**: Always review `terraform plan` output
4. **Test in Lower Environments**: Dev -> Staging -> Prod progression

### Security

1. **Never Commit Secrets**: Use environment variables or Key Vault
2. **Rotate Credentials**: Quarterly rotation for service principals
3. **Audit Access**: Regular review of who can modify configurations
4. **Encrypt State**: Use Azure Storage encryption for state files

### Environment Progression

1. **Development**:
   - Upgrade first, test thoroughly
   - Lower retention, smaller resources
   - Demo certificates acceptable

2. **Staging**:
   - Mirror production configuration
   - 2-3 days after dev upgrade
   - Validate before production

3. **Production**:
   - 7+ days after staging
   - Maintenance window required
   - Extended retention and storage
   - Real certificates only

### Naming Conventions

- Resource groups: `rg-<project>-<env>`
- AKS clusters: `aks-<project>-<env>`
- Storage accounts: `<project>tfstate<env><random>`
- Key vaults: `kv-<project>-<env>`

### Tagging Strategy

Standard tags for all resources:

```hcl
tags = {
  Environment = "dev|staging|prod"
  Project     = "AKS-GitOps"
  ManagedBy   = "Terraform"
  Owner       = "DevOps-Team"
  CostCenter  = "Engineering"
}
```

Production-specific tags:

```hcl
tags = {
  Criticality = "High"
  DataClass   = "Confidential"
}
```

## Related Documentation

- [Cluster Access Guide](./cluster-access-guide.md)
- [Deployment Guide](./deployment-guide.md)
- [AKS Cluster Upgrade Guide](./aks-cluster-upgrade-guide.md)
- [Security Guide](./security.md)
- [Production Update Strategy](./production-update-strategy.md)
