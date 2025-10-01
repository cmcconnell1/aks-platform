#!/bin/bash

# Bootstrap Validation Script for Azure AKS GitOps Platform
#
# This script validates that the bootstrap process has been completed correctly
# and all prerequisites are in place for successful Terraform deployment.
#
# Usage:
#   ./scripts/validate-bootstrap.sh
#   ./scripts/validate-bootstrap.sh --project-name "my-project" --environment dev

set -e

# ANSI color codes for consistent terminal output formatting
RED='\033[0;31m'      # Error messages and warnings
GREEN='\033[0;32m'    # Success messages and confirmations
YELLOW='\033[1;33m'   # Warning messages and important notes
BLUE='\033[0;34m'     # Informational messages and progress updates
NC='\033[0m'          # Reset to default terminal color

# Default configuration values
PROJECT_NAME="aks-platform"
ENVIRONMENT="dev"

# Utility functions for consistent colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo
    echo -e "${BLUE}=== $1 ===${NC}"
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --project-name)
                PROJECT_NAME="$2"
                shift 2
                ;;
            --environment)
                ENVIRONMENT="$2"
                shift 2
                ;;
            --help)
                show_help
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# Display help information
show_help() {
    echo "Bootstrap Validation Script"
    echo
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Options:"
    echo "  --project-name NAME      Project name (default: aks-platform)"
    echo "  --environment ENV        Environment to validate (default: dev)"
    echo "  --help                   Show this help message"
    echo
    echo "Examples:"
    echo "  $0                                    # Validate default project and dev environment"
    echo "  $0 --project-name my-project         # Validate custom project"
    echo "  $0 --environment prod                # Validate production environment"
}

# Check if required tools are installed
check_prerequisites() {
    print_header "Checking Prerequisites"
    
    local all_good=true
    
    # Check Azure CLI
    if command -v az >/dev/null 2>&1; then
        print_success "Azure CLI is installed"
        
        # Check if authenticated
        if az account show >/dev/null 2>&1; then
            local subscription_name=$(az account show --query name -o tsv)
            print_success "Authenticated with Azure (Subscription: $subscription_name)"
        else
            print_error "Not authenticated with Azure. Run 'az login'"
            all_good=false
        fi
    else
        print_error "Azure CLI is not installed"
        all_good=false
    fi
    
    # Check Terraform
    if command -v terraform >/dev/null 2>&1; then
        local tf_version=$(terraform version -json | jq -r '.terraform_version' 2>/dev/null || terraform version | head -n1 | cut -d' ' -f2)
        print_success "Terraform is installed (version: $tf_version)"
    else
        print_error "Terraform is not installed"
        all_good=false
    fi
    
    # Check kubectl
    if command -v kubectl >/dev/null 2>&1; then
        print_success "kubectl is installed"
    else
        print_warning "kubectl is not installed (optional for initial setup)"
    fi
    
    # Check GitHub CLI
    if command -v gh >/dev/null 2>&1; then
        if gh auth status >/dev/null 2>&1; then
            print_success "GitHub CLI is installed and authenticated"
        else
            print_warning "GitHub CLI is installed but not authenticated"
        fi
    else
        print_warning "GitHub CLI is not installed (required for GitHub secrets setup)"
    fi
    
    # Check Python
    if command -v python3 >/dev/null 2>&1; then
        local python_version=$(python3 --version | cut -d' ' -f2)
        print_success "Python 3 is installed (version: $python_version)"
        
        # Check virtual environment
        if [[ -n "$VIRTUAL_ENV" ]]; then
            print_success "Virtual environment is active: $VIRTUAL_ENV"
        else
            print_warning "No virtual environment active. Run 'source venv/bin/activate'"
        fi
    else
        print_error "Python 3 is not installed"
        all_good=false
    fi
    
    if [[ "$all_good" != true ]]; then
        print_error "Some prerequisites are missing. Please install them before proceeding."
        return 1
    fi
}

# Check if backend configuration exists
check_backend_config() {
    print_header "Checking Backend Configuration"
    
    local backend_file="terraform/environments/${ENVIRONMENT}/backend.conf"
    
    if [[ -f "$backend_file" ]]; then
        print_success "Backend configuration file exists: $backend_file"
        
        # Check if it has required fields
        local required_fields=("resource_group_name" "storage_account_name" "container_name" "key")
        local all_fields_present=true
        
        for field in "${required_fields[@]}"; do
            if grep -q "^${field}" "$backend_file"; then
                print_success "  OK $field is configured"
            else
                print_error "  ERROR $field is missing"
                all_fields_present=false
            fi
        done
        
        if [[ "$all_fields_present" == true ]]; then
            print_success "All required backend configuration fields are present"
        else
            print_error "Backend configuration is incomplete"
            return 1
        fi
    else
        print_error "Backend configuration file not found: $backend_file"
        print_status "Run: ./scripts/setup-azure-credentials.sh --project-name $PROJECT_NAME"
        return 1
    fi
}

# Check if terraform.tfvars exists
check_terraform_vars() {
    print_header "Checking Terraform Variables"

    local tfvars_file="terraform/environments/${ENVIRONMENT}/terraform.tfvars"

    if [[ -f "$tfvars_file" ]]; then
        print_success "Terraform variables file exists: $tfvars_file"

        # Check for key variables
        local key_vars=("project_name" "location" "environment")

        for var in "${key_vars[@]}"; do
            if grep -q "^${var}" "$tfvars_file"; then
                local value=$(grep "^${var}" "$tfvars_file" | cut -d'=' -f2 | tr -d ' "')
                print_success "  OK $var = $value"
            else
                print_warning "  ? $var is not explicitly set (may use default)"
            fi
        done

        # Check if file is committed to git
        if git ls-files --error-unmatch "$tfvars_file" >/dev/null 2>&1; then
            print_warning "  WARNING: terraform.tfvars is committed to git (security risk)"
            print_status "    Consider using environment variables in CI/CD instead"
        else
            print_success "  OK terraform.tfvars is not committed (good security practice)"
            print_status "    GitHub Actions uses TF_VAR_ environment variables instead"
        fi
    else
        print_warning "Terraform variables file not found: $tfvars_file"
        print_status "This is normal for CI/CD environments that use TF_VAR_ environment variables"
        print_status "For local development, run: ./scripts/setup-azure-credentials.sh --project-name $PROJECT_NAME"
    fi
}

# Check if Azure resources exist
check_azure_resources() {
    print_header "Checking Azure Resources"
    
    # Extract storage account name from backend config
    local backend_file="terraform/environments/${ENVIRONMENT}/backend.conf"
    local storage_account=$(grep "storage_account_name" "$backend_file" | cut -d'=' -f2 | tr -d ' "')
    local resource_group=$(grep "resource_group_name" "$backend_file" | cut -d'=' -f2 | tr -d ' "')
    
    if [[ -n "$storage_account" && -n "$resource_group" ]]; then
        # Check if storage account exists
        if az storage account show --name "$storage_account" --resource-group "$resource_group" >/dev/null 2>&1; then
            print_success "Storage account exists: $storage_account"
        else
            print_error "Storage account not found: $storage_account in $resource_group"
            print_status "Run: ./scripts/setup-azure-credentials.sh --project-name $PROJECT_NAME"
            return 1
        fi
        
        # Check if container exists
        if az storage container show --name "tfstate" --account-name "$storage_account" >/dev/null 2>&1; then
            print_success "Storage container 'tfstate' exists"
        else
            print_error "Storage container 'tfstate' not found"
            return 1
        fi
    else
        print_error "Could not extract storage account information from backend config"
        return 1
    fi
}

# Check Terraform provider configuration
check_terraform_providers() {
    print_header "Checking Terraform Provider Configuration"
    
    local terraform_file="terraform/terraform.tf"
    
    if [[ -f "$terraform_file" ]]; then
        print_success "Main Terraform configuration exists: $terraform_file"
        
        # Check for required providers
        local required_providers=("azurerm" "azuread" "kubernetes" "helm" "kubectl" "http")
        
        for provider in "${required_providers[@]}"; do
            if grep -q "source.*$provider" "$terraform_file"; then
                print_success "  OK $provider provider is configured"
            else
                print_error "  ERROR $provider provider is missing"
                return 1
            fi
        done
        
        # Check for kubectl provider source
        if grep -q "gavinbunney/kubectl" "$terraform_file"; then
            print_success "  OK kubectl provider uses correct source (gavinbunney/kubectl)"
        else
            print_error "  ERROR kubectl provider should use 'gavinbunney/kubectl' source"
            return 1
        fi
    else
        print_error "Main Terraform configuration not found: $terraform_file"
        return 1
    fi
}

# Test Terraform initialization
test_terraform_init() {
    print_header "Testing Terraform Initialization"
    
    cd terraform
    
    if terraform init -backend-config="environments/${ENVIRONMENT}/backend.conf" >/dev/null 2>&1; then
        print_success "Terraform initialization successful"
        cd ..
        return 0
    else
        print_error "Terraform initialization failed"
        print_status "Try running: cd terraform && terraform init -backend-config=\"environments/${ENVIRONMENT}/backend.conf\""
        cd ..
        return 1
    fi
}

# Display summary
display_summary() {
    print_header "Bootstrap Validation Summary"
    
    echo
    print_success "Bootstrap validation completed successfully!"
    echo
    print_status "Your environment is ready for Terraform deployment:"
    echo "  • Prerequisites are installed and configured"
    echo "  • Backend configuration is valid"
    echo "  • Azure resources are accessible"
    echo "  • Terraform providers are properly configured"
    echo "  • Terraform can initialize successfully"
    echo
    print_status "Next steps:"
    echo "  1. Commit any remaining configuration files"
    echo "  2. Push to trigger GitHub Actions deployment"
    echo "  3. Monitor deployment in GitHub Actions"
    echo
    print_status "Useful commands:"
    echo "  • Check deployment: gh run list"
    echo "  • View logs: gh run view <run-id> --log"
    echo "  • Manual deployment: cd terraform && terraform plan"
}

# Main execution function
main() {
    parse_arguments "$@"
    
    print_status "Starting bootstrap validation for project: $PROJECT_NAME (environment: $ENVIRONMENT)"
    echo
    
    # Run all validation checks
    local validation_failed=false
    
    check_prerequisites || validation_failed=true
    check_backend_config || validation_failed=true
    check_terraform_vars || validation_failed=true
    check_azure_resources || validation_failed=true
    check_terraform_providers || validation_failed=true
    test_terraform_init || validation_failed=true
    
    if [[ "$validation_failed" == true ]]; then
        print_error "Bootstrap validation failed. Please address the issues above."
        exit 1
    else
        display_summary
    fi
}

# Run main function with all arguments
main "$@"
