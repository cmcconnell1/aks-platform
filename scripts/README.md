# Scripts Directory

This directory contains automation scripts for setting up and managing the Azure AKS GitOps platform. Each script is designed to handle specific aspects of the deployment and management process.

## Script Overview

| Script | Purpose | Type | Prerequisites |
|--------|---------|------|---------------|
| [`setup-azure-credentials.sh`](#setup-azure-credentialssh) | **Azure setup** (simple wrapper) | Shell Wrapper | Azure CLI |
| [`setup-azure-credentials.py`](#setup-azure-credentialspy) | Azure setup (core implementation) | Python Core | Azure CLI, Python packages |
| [`setup-github-secrets.sh`](#setup-github-secretssh) | GitHub repository secrets configuration | Shell Script | GitHub CLI |
| [`cost-monitor.sh`](#cost-monitorsh) | **Unified cost monitoring** (wrapper) | Shell Wrapper | Azure CLI (optional) |
| [`azure-cost-monitor.py`](#azure-cost-monitorpy) | Cost monitoring (core implementation) | Python Core | Azure SDK packages |
| [`cost-dashboard.sh`](#cost-dashboardsh) | HTML dashboard for cost visualization | Shell Script | Azure CLI, Python, jq |
| [`safe-deployment.sh`](#safe-deploymentsh) | Production-safe deployment with rollback | Shell Script | Azure CLI, kubectl |
| [`cleanup-infrastructure.sh`](#cleanup-infrastructuresh) | Complete infrastructure removal | Shell Script | Azure CLI, Terraform |
| [`show-infrastructure.sh`](#show-infrastructuresh) | **Infrastructure overview** (wrapper) | Shell Wrapper | Azure CLI |
| [`show-infrastructure.py`](#show-infrastructurepy) | Infrastructure overview (core implementation) | Python Core | Azure CLI, Python packages |
| [`module-check.py`](#module-checkpy) | Python module dependency analysis | Python Utility | None |
| [`azure_utils.py`](#azure_utilspy) | Shared utilities for Python scripts | Python Module | Azure CLI (optional) |
| [`setup-python-env.sh`](#setup-python-envsh) | **Python virtual environment setup** | Shell Script | Python 3.7+ |
| [`check-python-env.py`](#check-python-envpy) | Python environment checker | Python Utility | None |
| [`validate-bootstrap.sh`](#validate-bootstrapsh) | **Bootstrap validation and readiness check** | Shell Script | Azure CLI, Terraform |
| [`manage-dependencies.py`](#manage-dependenciespy) | Dependency management and security audit | Python Utility | Virtual environment |
| [`venv-utils.sh`](#venv-utilssh) | Virtual environment utilities for shell scripts | Shell Library | None |

## Quick Start

### 0. Python Environment Setup (Recommended)

Set up a virtual environment for better dependency management:

```bash
# Automated setup with all dependencies
./scripts/setup-python-env.sh

# Or with development tools
./scripts/setup-python-env.sh --dev

# Check environment status
python3 scripts/check-python-env.py

# Manual setup (alternative)
python3 -m venv venv
source venv/bin/activate
pip install -r scripts/requirements.txt
```

**Why use virtual environments?**
- Isolate project dependencies from system Python
- Ensure reproducible environments across different machines
- Prevent conflicts between different projects
- Follow Python development best practices

### 1. Initial Azure Setup
```bash
# Simple wrapper (recommended - handles dependencies automatically)
./scripts/setup-azure-credentials.sh

# Direct Python script (advanced users)
python3 scripts/setup-azure-credentials.py

# With automatic dependency installation
./scripts/setup-azure-credentials.sh --install-deps
```

### 2. Bootstrap Validation
```bash
# Validate that bootstrap completed successfully
./scripts/validate-bootstrap.sh

# Validate specific project/environment
./scripts/validate-bootstrap.sh --project-name "my-project" --environment prod
```

### 3. GitHub Integration
```bash
# Configure GitHub repository secrets
gh auth login
./scripts/setup-github-secrets.sh
```

### 3. Safe Production Deployment
```bash
# Production deployment with safety checks
./scripts/safe-deployment.sh --environment prod --component infrastructure

# Dry run to preview changes
./scripts/safe-deployment.sh --environment staging --component all --dry-run
```

### 4. Unified Cost Monitoring
```bash
# Current month actual costs (uses default: aks-platform)
./scripts/cost-monitor.sh

# With custom project name
./scripts/cost-monitor.sh --project-name "acme-platform"

# Cost estimation for planning
./scripts/cost-monitor.sh --estimate --env dev --region westus

# Production costs with budget alerts
./scripts/cost-monitor.sh --actual --env prod --budget 1000

# Generate and serve live dashboard
./scripts/cost-monitor.sh --dashboard --serve --port 8080

# Set up daily monitoring with notifications
./scripts/cost-monitor.sh --schedule daily --budget 500 --webhook "https://hooks.slack.com/..."
```

### 5. Infrastructure Cleanup
```bash
# Complete infrastructure removal
./scripts/cleanup-infrastructure.sh --project-name "my-project" --yes
```

## Script Architecture

### Hybrid Approach: Shell Wrappers + Python Core

The scripts follow a **hybrid architecture** that provides the best of both worlds:

- **Shell Wrappers**: Simple, user-friendly interfaces that handle dependencies and provide clear error messages
- **Python Core**: Robust implementations with proper error handling, cross-platform compatibility, and advanced features
- **Shared Utilities**: Common functionality in `azure_utils.py` to reduce duplication

### Benefits

1. **User-Friendly**: Simple shell commands for common operations
2. **Robust**: Python core provides reliable functionality
3. **Cross-Platform**: Works on Windows, macOS, and Linux
4. **Maintainable**: Single source of truth for core logic
5. **Flexible**: Choose shell wrapper or direct Python based on needs

## Detailed Script Documentation

### `setup-azure-credentials.sh`

**Purpose**: Simple wrapper for Azure credentials setup that handles dependencies automatically.

**Key Features**:
- **Automatic dependency checking**: Verifies Python, Azure CLI, and packages
- **User-friendly interface**: Clear error messages and progress indicators
- **Cross-platform compatibility**: Works on Windows, macOS, Linux
- **Automatic installation**: Can install Python dependencies automatically

**Usage**:
```bash
# Basic setup with defaults
./scripts/setup-azure-credentials.sh

# Custom project and location
./scripts/setup-azure-credentials.sh --project-name "my-project" --location "West US 2"

# Auto-install dependencies
./scripts/setup-azure-credentials.sh --install-deps

# Get help
./scripts/setup-azure-credentials.sh --help
```

**Prerequisites**:
- Python 3.7+
- Azure CLI (logged in with `az login`)
- Internet connection for package installation

**Generated Files**:
- `terraform/environments/*/backend.conf` - Terraform backend configuration
- `terraform/environments/*/terraform.tfvars` - Environment variables
- Service principal credentials (displayed once, store securely)

**Security Features**:
- Least-privilege access principles
- Storage account encryption enabled
- Secure state locking with blob leases
- Credential rotation guidance

### `setup-azure-credentials.py`

**Purpose**: Core Python implementation for Azure credentials and infrastructure setup.

**Advanced Features**:
- **Robust error handling**: Comprehensive validation and error recovery
- **Detailed logging**: Progress reporting and debugging information
- **JSON output**: Machine-readable output for automation
- **Configuration management**: Saves settings for future use
- **Retry logic**: Handles transient Azure API failures

**Direct Usage** (Advanced):
```bash
# Basic setup
python3 scripts/setup-azure-credentials.py

# With custom parameters
python3 scripts/setup-azure-credentials.py \
  --project-name "my-project" \
  --location "westus2" \
  --resource-group-name "my-rg" \
  --storage-account-name "mystorageacct"

# JSON output for automation
python3 scripts/setup-azure-credentials.py --output-format json
```

**What it creates**:
- Service principal for Terraform operations
- Storage account for Terraform state
- Resource group for shared resources
- GitHub secrets configuration file
- Local configuration cache

### `setup-github-secrets.sh`

**Purpose**: Configures GitHub repository secrets for CI/CD pipeline automation.

**Configured Secrets**:
- `AZURE_CLIENT_ID` - Service principal application ID
- `AZURE_CLIENT_SECRET` - Service principal password
- `AZURE_TENANT_ID` - Azure Active Directory tenant ID
- `AZURE_SUBSCRIPTION_ID` - Target Azure subscription
- `INFRACOST_API_KEY` - Cost estimation integration (optional)
- `SLACK_WEBHOOK_URL` - Deployment notifications (optional)

**Usage**:
```bash
# Ensure GitHub CLI is authenticated
gh auth login

# Run the setup script
./scripts/setup-github-secrets.sh
```

**Environment Protection**:
The script guides you through setting up:
- Required reviewers for production deployments
- Branch protection policies
- Environment-specific access controls

### `cost-monitor.sh`

**Purpose**: Unified cost monitoring solution that combines cost estimation, actual billing monitoring, and dashboard generation in a single tool.

**Key Features**:
- **Cost Estimation**: Quick estimates using Azure pricing data with regional variations
- **Actual Cost Monitoring**: Real-time billing data via Azure Cost Management API
- **Dashboard Generation**: HTML dashboards with auto-refresh capabilities
- **Budget Alerts**: Threshold monitoring with webhook notifications
- **Automated Scheduling**: Cron job setup for regular monitoring
- **Multi-Environment Support**: Dev, staging, production cost tracking

**Modes of Operation**:

#### Estimation Mode (`--estimate`)
- Quick cost estimates using static pricing data
- Regional cost variations (up to 30% difference)
- Currency conversion support
- Environment-specific sizing (dev/staging/prod)

**Usage**:
```bash
# Basic cost estimation
./scripts/cost-monitor.sh --estimate --env dev

# With custom region
./scripts/cost-monitor.sh --estimate --region westus2

# Export estimation data
./scripts/cost-monitor.sh --estimate --export estimates.json
```

#### Actual Cost Mode (`--actual`, default)
- Real Azure billing data via Cost Management API
- Project-specific resource filtering
- Environment-based cost breakdown
- Budget threshold monitoring

**Usage**:
```bash
# Current month actual costs
./scripts/cost-monitor.sh --actual --project-name "my-project"

# Specific environment with budget alerts
./scripts/cost-monitor.sh --actual --env prod --budget 1000

# Last 30 days with notifications
./scripts/cost-monitor.sh --actual --days 30 --webhook "https://hooks.slack.com/..."
```

#### Dashboard Mode (`--dashboard`)
- HTML dashboard generation with cost visualization
- Auto-refresh capabilities for live monitoring
- Budget alert indicators with color coding
- HTTP server for dashboard serving

**Usage**:
```bash
# Generate static dashboard
./scripts/cost-monitor.sh --dashboard --output costs.html

# Serve live dashboard
./scripts/cost-monitor.sh --dashboard --serve --port 8080

# Dashboard with budget monitoring
./scripts/cost-monitor.sh --dashboard --budget 1000 --serve
```

**Estimated Costs** (East US, monthly):
- **Development**: $220-650 (base/with AI/ML)
- **Staging**: $380-1220 (base/with AI/ML)
- **Production**: $1000-3600 (base/with AI/ML)

**Scheduling and Automation**:
```bash
# Set up daily monitoring
./scripts/cost-monitor.sh --schedule daily --budget 1000

# Weekly monitoring with notifications
./scripts/cost-monitor.sh --schedule weekly --webhook "URL"
```

### `azure-cost-monitor.py`

**Purpose**: Monitors actual Azure billing costs for infrastructure deployed by the platform using Azure Cost Management API.

**Key Features**:
- Real-time cost analysis using Azure Cost Management API
- Project-specific cost filtering using resource tags and naming conventions
- Environment-based cost breakdown (dev, staging, prod)
- Budget alerts and threshold monitoring
- Cost trend analysis and forecasting
- Export capabilities for reporting and analysis

**Prerequisites**:
```bash
# Install required packages
pip install azure-mgmt-costmanagement azure-identity azure-mgmt-resource requests

# Ensure Azure CLI authentication
az login
```

**Usage**:
```bash
# Current month costs for entire project
python3 scripts/azure-cost-monitor.py --project-name "my-project"

# Specific environment costs
python3 scripts/azure-cost-monitor.py --environment prod --days 30

# With budget alerts
python3 scripts/azure-cost-monitor.py --budget-alert 1000 --export costs.json

# Quiet mode for scripting
python3 scripts/azure-cost-monitor.py --quiet
```

**Cost Analysis Features**:
- Automatic resource group discovery based on project naming conventions
- Daily cost breakdown and trend analysis
- Service-level cost categorization
- Budget utilization percentage calculation
- Critical/warning/ok status indicators

### `cost-monitor.sh`

**Purpose**: Convenient wrapper around the Python cost monitor with scheduling and notification capabilities.

**Enhanced Features**:
- Simplified command-line interface
- Automatic dependency checking and installation
- Cron job scheduling for regular monitoring
- Webhook notifications for budget alerts (Slack, Teams, etc.)
- Historical cost tracking and trend analysis

**Usage**:
```bash
# Basic cost monitoring
./scripts/cost-monitor.sh --project-name "my-project"

# Environment-specific monitoring
./scripts/cost-monitor.sh --env prod --days 7

# With budget alerts and notifications
./scripts/cost-monitor.sh --budget 1000 --webhook "https://hooks.slack.com/services/..."

# Set up automated daily monitoring
./scripts/cost-monitor.sh --schedule daily --budget 500

# Quiet mode for cron jobs
./scripts/cost-monitor.sh --quiet --export /var/log/azure-costs.json
```

**Scheduling Options**:
- `daily` - Monitor costs every day at 9 AM
- `weekly` - Monitor costs every Monday at 9 AM
- `monthly` - Monitor costs on the 1st of each month at 9 AM

**Notification Integration**:
Supports webhook notifications for:
- Budget threshold alerts (75%, 90%, 100%+)
- Daily/weekly cost summaries
- Critical cost overruns

### `cost-dashboard.sh`

**Purpose**: Generates a real-time HTML dashboard for visualizing Azure costs with auto-refresh capabilities.

**Dashboard Features**:
- Real-time cost monitoring with auto-refresh
- Budget alert visualization with color-coded status
- Cost breakdown by resource group with percentages
- Quick action buttons for Azure Portal access
- Responsive design for desktop and mobile viewing

**Usage**:
```bash
# Generate static HTML dashboard
./scripts/cost-dashboard.sh --project-name "my-project" --output dashboard.html

# Serve live dashboard with auto-refresh
./scripts/cost-dashboard.sh --serve --port 8080 --budget 1000

# Custom refresh interval (default: 300 seconds)
./scripts/cost-dashboard.sh --serve --refresh 180
```

**Dashboard Components**:
- **Header**: Project name, last update timestamp
- **Cost Summary**: Current month total with period information
- **Budget Alerts**: Color-coded alerts (green/yellow/red) with percentage usage
- **Cost Breakdown**: Table showing costs by resource group with percentages
- **Quick Actions**: Refresh button and Azure Portal link

**Auto-Refresh Features**:
- Configurable refresh interval (default: 5 minutes)
- Background data updates without page reload
- Real-time timestamp updates
- Automatic browser refresh on data changes

### `safe-deployment.sh`

**Purpose**: Implements production-safe deployment procedures with comprehensive safety mechanisms.

**Key Features**:
- Pre-deployment health baseline establishment
- Automatic backup creation before changes
- Real-time monitoring during deployment
- Automatic rollback on failure detection
- Post-deployment validation and reporting
- Support for dry-run mode

**Safety Mechanisms**:
- Health checks before, during, and after deployment
- Automatic backup of Terraform state and Kubernetes resources
- Progressive deployment with validation checkpoints
- Configurable rollback triggers
- Comprehensive error handling and logging

**Usage**:
```bash
# Production infrastructure deployment
./scripts/safe-deployment.sh --environment prod --component infrastructure

# Platform services with monitoring
./scripts/safe-deployment.sh --environment staging --component platform-services

# Dry run to preview changes
./scripts/safe-deployment.sh --environment prod --component all --dry-run

# Deployment without automatic rollback
./scripts/safe-deployment.sh --environment dev --component applications --no-rollback
```

**Component Types**:
- `infrastructure` - Terraform-managed Azure resources
- `platform-services` - ArgoCD, monitoring, AI/ML tools
- `applications` - Application manifests and configurations
- `all` - Complete deployment of all components

**Options**:
- `--dry-run` - Show what would be deployed without making changes
- `--no-backup` - Skip pre-deployment backup creation
- `--no-rollback` - Disable automatic rollback on failure

### `cleanup-infrastructure.sh`

**Purpose**: Safely removes all infrastructure deployed by the platform with proper cleanup order.

**Key Features**:
- Kubernetes resource cleanup with proper order
- Terraform infrastructure destruction
- Azure resource group removal
- Service principal cleanup
- Local configuration file cleanup
- Comprehensive verification of cleanup completion

**Safety Features**:
- User confirmation prompts
- Backup creation before cleanup
- Force cleanup mode for stuck resources
- Detailed progress reporting
- Verification of complete removal

**Usage**:
```bash
# Interactive cleanup with confirmations
./scripts/cleanup-infrastructure.sh --project-name "my-project"

# Automated cleanup without prompts
./scripts/cleanup-infrastructure.sh --project-name "my-project" --yes

# Force cleanup for stuck resources
./scripts/cleanup-infrastructure.sh --project-name "my-project" --force --yes
```

### `module-check.py`

**Purpose**: Analyzes Python scripts to identify module dependencies and compatibility issues.

**Features**:
- Python 3 compatible module analysis
- Automatic fallback when ModuleFinder fails
- Module classification (standard library, third-party, local)
- Requirements.txt generation suggestions
- Cross-platform compatibility

**Usage**:
```bash
# Analyze specific script
python3 scripts/module-check.py ./scripts/setup-azure-credentials.py

# Analyze default script
python3 scripts/module-check.py

# Make executable and run
chmod +x scripts/module-check.py
./scripts/module-check.py
```

### `azure_utils.py`

**Purpose**: Shared utilities module for Python scripts to reduce code duplication and ensure consistency.

**Key Components**:
- **AzureHelper**: Common Azure operations (subscription info, resource groups, authentication)
- **ConfigManager**: Configuration management with persistent storage
- **DependencyChecker**: Automated dependency checking and installation
- **Utility Functions**: Consistent logging, error handling, and formatting

**Features**:
- **Consistent Error Handling**: Standardized error messages and logging
- **Cross-Platform Compatibility**: Works on Windows, macOS, Linux
- **Configuration Persistence**: Saves settings for reuse across scripts
- **Dependency Management**: Automatic checking and installation of requirements

**Usage in Other Scripts**:
```python
from azure_utils import AzureHelper, print_status, print_error

# Azure operations
helper = AzureHelper()
subscription_id = helper.get_subscription_id()
resource_groups = helper.get_resource_groups("my-project")

# Consistent logging
print_status("Starting operation...")
print_success("Operation completed successfully")

# Configuration management
from azure_utils import ConfigManager
config = ConfigManager()
project_name = config.get('project_name', 'default-project')
```

**Shared Functionality**:
- Azure CLI authentication checking
- Subscription and resource group operations
- Consistent color-coded terminal output
- Configuration file management
- Dependency validation and installation

## Script Dependencies

### System Requirements
- **Bash Scripts**: Bash 4.0+, standard Unix tools (grep, sed, awk)
- **Python Scripts**: Python 3.7+, pip package manager
- **Azure CLI**: Version 2.40.0 or later
- **GitHub CLI**: Version 2.0 or later (for GitHub integration)

### Python Package Dependencies
```bash
# For setup-azure-credentials.py
pip install azure-cli azure-identity azure-mgmt-storage azure-mgmt-authorization

# For dynamic-cost-estimator.py
pip install requests

# For module-check.py (uses only standard library)
# No additional packages required
```

### Script Dependencies Matrix

| Script | Type | Azure CLI | GitHub CLI | kubectl | Terraform | Python Packages | Other Tools |
|--------|------|-----------|------------|---------|-----------|------------------|-------------|
| setup-azure-credentials.sh | Wrapper | Required | - | - | - | - | - |
| setup-azure-credentials.py | Core | Required | - | - | - | azure-* packages | - |
| setup-github-secrets.sh | Script | - | Required | - | - | - | - |
| cost-monitor.sh | Wrapper | Optional* | - | - | - | Optional* | bc, cron |
| azure-cost-monitor.py | Core | Required | - | - | - | azure-mgmt-* packages | - |
| cost-dashboard.sh | Script | Required | - | - | - | - | jq, HTTP server |
| safe-deployment.sh | Script | Required | - | Required | Required | - | - |
| cleanup-infrastructure.sh | Script | Required | - | Optional | Optional | - | - |
| module-check.py | Utility | - | - | - | - | - | - |
| azure_utils.py | Module | Optional | - | - | - | azure-* packages | - |

**Notes**:
- **Wrapper**: Simple shell interface that calls Python core
- **Core**: Python implementation with robust functionality
- **Script**: Standalone shell script
- **Utility**: Helper tool or module
- **Optional***: Required only for specific modes (e.g., `--actual` mode for cost monitoring)

### `setup-python-env.sh`

**Purpose**: Automated Python virtual environment setup with dependency management.

**Key Features**:
- **Virtual environment creation**: Creates isolated Python environments
- **Dependency installation**: Installs production and development dependencies
- **Cross-platform support**: Works on Linux, macOS, and Windows (Git Bash/WSL)
- **Helper script generation**: Creates activation shortcuts
- **Comprehensive validation**: Checks Python version and virtual environment support

**Usage**:
```bash
# Basic setup
./scripts/setup-python-env.sh

# With development dependencies
./scripts/setup-python-env.sh --dev

# Custom virtual environment name
./scripts/setup-python-env.sh --venv-name .venv

# Force recreation
./scripts/setup-python-env.sh --force

# Get help
./scripts/setup-python-env.sh --help
```

**Generated Files**:
- `venv/` or `.venv/` - Virtual environment directory
- `activate-python-env.sh` - Helper activation script

### `check-python-env.py`

**Purpose**: Comprehensive Python environment checker and diagnostic tool.

**Key Features**:
- **Environment detection**: Checks if running in virtual environment
- **Version validation**: Ensures Python 3.7+ compatibility
- **Dependency analysis**: Lists installed and missing packages
- **Recommendations**: Provides setup guidance and next steps
- **Status reporting**: Clear summary of environment health

**Usage**:
```bash
# Check current environment
python3 scripts/check-python-env.py

# Make executable and run
chmod +x scripts/check-python-env.py
./scripts/check-python-env.py
```

### `manage-dependencies.py`

**Purpose**: Advanced dependency management with security auditing.

**Key Features**:
- **Dependency checking**: Validates installed packages against requirements
- **Security auditing**: Scans for known vulnerabilities using pip-audit/safety
- **Update management**: Updates packages to latest compatible versions
- **Requirements generation**: Creates frozen requirements files
- **Outdated package detection**: Identifies packages needing updates

**Usage**:
```bash
# Check dependencies
python3 scripts/manage-dependencies.py check

# Security audit
python3 scripts/manage-dependencies.py audit

# Update packages (dry run)
python3 scripts/manage-dependencies.py update --dry-run

# Generate frozen requirements
python3 scripts/manage-dependencies.py freeze

# Show outdated packages
python3 scripts/manage-dependencies.py outdated
```

### `validate-bootstrap.sh`

**Purpose**: Comprehensive bootstrap validation script that ensures all prerequisites and configurations are in place for successful Terraform deployment.

**Key Features**:
- **Prerequisites checking**: Validates Azure CLI, Terraform, Python, and other required tools
- **Configuration validation**: Checks backend.conf and terraform.tfvars files
- **Azure resource verification**: Confirms storage accounts and containers exist
- **Provider validation**: Ensures all Terraform providers are correctly configured
- **Terraform initialization test**: Validates that Terraform can initialize successfully
- **Detailed reporting**: Provides clear success/failure status with actionable guidance

**Usage**:
```bash
# Basic validation with defaults
./scripts/validate-bootstrap.sh

# Validate specific project and environment
./scripts/validate-bootstrap.sh --project-name "my-project" --environment prod

# Get help
./scripts/validate-bootstrap.sh --help
```

**Validation Checks**:
1. **Prerequisites**: Azure CLI authentication, Terraform installation, Python environment
2. **Backend Configuration**: Validates backend.conf file structure and required fields
3. **Terraform Variables**: Checks terraform.tfvars file existence and key variables
4. **Azure Resources**: Verifies storage account and container accessibility
5. **Provider Configuration**: Ensures all required providers are declared correctly
6. **Terraform Initialization**: Tests actual Terraform init process

**Common Issues Detected**:
- Missing or incorrect kubectl provider source (should be gavinbunney/kubectl)
- Storage account not found (bootstrap not completed)
- Missing backend configuration files
- Authentication issues with Azure or GitHub
- Virtual environment not activated

### `venv-utils.sh`

**Purpose**: Shared virtual environment utilities for shell scripts.

**Key Features**:
- **Environment detection**: Functions to check virtual environment status
- **Package installation**: Virtual environment-aware package management
- **Activation helpers**: Utilities for finding and activating environments
- **Status reporting**: Functions for environment status display
- **Integration support**: Easy integration into existing shell scripts

**Usage** (in shell scripts):
```bash
# Source the utilities
source scripts/venv-utils.sh

# Check virtual environment
check_virtual_environment

# Install packages with virtual environment awareness
install_python_packages_with_venv "package1" "package2"

# Show environment status
show_venv_status
```

## Python Development Best Practices

### Virtual Environment Workflow
1. **Always use virtual environments** for Python development
2. **Create project-specific environments** - never share between projects
3. **Activate before installing packages** - `source venv/bin/activate`
4. **Pin dependency versions** in requirements.txt for reproducibility
5. **Regular security audits** of dependencies

### Dependency Management
1. **Use requirements files** for different purposes:
   - `requirements.txt` - Production dependencies
   - `requirements-dev.txt` - Development tools
   - `requirements-test.txt` - Testing frameworks
2. **Pin exact versions** for production deployments
3. **Regular updates** with thorough testing
4. **Security scanning** with pip-audit or safety

### Development Tools Integration
```bash
# Use Makefile for common tasks
make setup-dev    # Set up development environment
make check        # Run all quality checks
make test         # Run test suite
make format       # Format code
make clean        # Clean up environment

# Or use individual tools
python3 scripts/manage-dependencies.py audit
python3 scripts/check-python-env.py
```

## Security Considerations

### Credential Handling
- Service principal credentials are displayed only once during creation
- Scripts never store credentials in files or logs
- GitHub secrets are encrypted at rest
- Least-privilege access principles applied

### Best Practices
1. **Rotate credentials quarterly** using the setup scripts
2. **Use separate service principals** for different environments
3. **Monitor access logs** in Azure Active Directory
4. **Review permissions regularly** and remove unused principals
5. **Enable MFA** on accounts with administrative access

## Troubleshooting

### Common Issues

**Azure CLI not authenticated**:
```bash
az login
az account set --subscription "your-subscription-id"
```

**GitHub CLI not authenticated**:
```bash
gh auth login
gh auth status  # Verify authentication
```

**Permission errors**:
- Ensure your Azure account has sufficient permissions
- Check if you're in the correct subscription
- Verify service principal permissions

**Python package errors**:
```bash
pip install --upgrade pip
pip install -r scripts/requirements.txt
```

### Getting Help

1. **Check script output** - All scripts provide detailed error messages
2. **Review prerequisites** - Ensure all required tools are installed
3. **Validate permissions** - Check Azure and GitHub access rights
4. **Consult documentation** - Refer to the main project documentation
5. **Open an issue** - Report bugs or request features on GitHub

## Additional Resources

- [Azure CLI Documentation](https://docs.microsoft.com/en-us/cli/azure/)
- [GitHub CLI Documentation](https://cli.github.com/manual/)
- [Azure Pricing Calculator](https://azure.microsoft.com/pricing/calculator/)
- [Terraform Azure Provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)
- [Azure Service Principal Best Practices](https://docs.microsoft.com/en-us/azure/active-directory/develop/howto-create-service-principal-portal)

## Contributing

When modifying scripts:
1. **Maintain backward compatibility** where possible
2. **Add comprehensive comments** for complex logic
3. **Test on multiple platforms** (Linux, macOS, Windows)
4. **Update this README** with any new features or changes
5. **Follow existing code style** and error handling patterns
