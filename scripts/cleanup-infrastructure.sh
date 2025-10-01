#!/bin/bash

# Infrastructure Cleanup Script for Azure AKS GitOps Platform
#
# This script provides automated cleanup of all infrastructure deployed by the
# Azure AKS GitOps platform project. It safely removes resources in the correct
# order to avoid dependency conflicts.
#
# WARNING: THIS WILL DELETE ALL INFRASTRUCTURE AND DATA
#
# What this script does:
# 1. Removes Kubernetes applications and platform services
# 2. Destroys Terraform-managed infrastructure
# 3. Cleans up service principals and Azure AD applications
# 4. Removes Terraform state and local configuration files
# 5. Provides verification of complete cleanup
#
# Prerequisites:
#   - Azure CLI installed and authenticated
#   - Terraform installed
#   - kubectl configured (if AKS clusters exist)
#   - Appropriate permissions to delete resources
#
# Usage:
#   ./scripts/cleanup-infrastructure.sh
#   ./scripts/cleanup-infrastructure.sh --project-name "my-project" --force

set -e  # Exit immediately if any command fails

# ANSI color codes for consistent terminal output formatting
RED='\033[0;31m'      # Error messages and warnings
GREEN='\033[0;32m'    # Success messages and confirmations
YELLOW='\033[1;33m'   # Warning messages and important notes
BLUE='\033[0;34m'     # Informational messages and progress updates
NC='\033[0m'          # Reset to default terminal color

# Default configuration values
PROJECT_NAME="aks-platform"
ENVIRONMENTS=("dev" "staging" "prod")
FORCE_CLEANUP=false
SKIP_CONFIRMATION=false

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

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --project-name)
                PROJECT_NAME="$2"
                shift 2
                ;;
            --environment)
                ENVIRONMENTS=("$2")
                shift 2
                ;;
            --force)
                FORCE_CLEANUP=true
                shift
                ;;
            --yes)
                SKIP_CONFIRMATION=true
                shift
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
    echo "Azure AKS GitOps Platform Cleanup Script"
    echo
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Options:"
    echo "  --project-name NAME      Project name (default: aks-platform)"
    echo "  --environment ENV        Clean up specific environment only (dev, staging, prod)"
    echo "  --force                  Force cleanup even if errors occur"
    echo "  --yes                    Skip confirmation prompts"
    echo "  --help                   Show this help message"
    echo
    echo "Examples:"
    echo "  $0                                      # Interactive cleanup (all environments)"
    echo "  $0 --environment dev --yes              # Clean up dev environment only"
    echo "  $0 --project-name my-project --yes     # Automated cleanup"
    echo "  $0 --force                             # Force cleanup with error handling"
}

# Confirm cleanup operation with user
confirm_cleanup() {
    if [ "$SKIP_CONFIRMATION" = true ]; then
        return 0
    fi

    echo
    print_warning "INFRASTRUCTURE CLEANUP WARNING"
    echo
    echo "This script will PERMANENTLY DELETE the following:"
    echo "  - All AKS clusters and workloads"
    echo "  - Application Gateway and networking"
    echo "  - Key Vault and all certificates/secrets"
    echo "  - Storage accounts and Terraform state"
    echo "  - Service principals and Azure AD applications"
    echo "  - All data in persistent volumes"
    echo
    echo "Project: $PROJECT_NAME"
    echo "Environments: ${ENVIRONMENTS[*]}"
    echo
    print_error "THIS ACTION CANNOT BE UNDONE!"
    echo
    read -p "Type 'DELETE EVERYTHING' to confirm: " confirmation
    
    if [ "$confirmation" != "DELETE EVERYTHING" ]; then
        print_status "Cleanup cancelled by user"
        exit 0
    fi
    
    print_success "Cleanup confirmed. Starting infrastructure removal..."
}

# Check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    # Check if Azure CLI is installed and authenticated
    if ! command -v az >/dev/null 2>&1; then
        print_error "Azure CLI is not installed"
        exit 1
    fi
    
    if ! az account show >/dev/null 2>&1; then
        print_error "Not logged in to Azure. Please run 'az login' first"
        exit 1
    fi
    
    # Check if Terraform is installed
    if ! command -v terraform >/dev/null 2>&1; then
        print_warning "Terraform not found. Terraform cleanup will be skipped"
    fi
    
    # Check if kubectl is available
    if ! command -v kubectl >/dev/null 2>&1; then
        print_warning "kubectl not found. Kubernetes cleanup will be skipped"
    fi
    
    print_success "Prerequisites check completed"
}

# Clean up Kubernetes resources
cleanup_kubernetes() {
    print_status "Cleaning up Kubernetes resources..."
    
    for env in "${ENVIRONMENTS[@]}"; do
        print_status "Processing $env environment..."
        
        # Try to get AKS credentials
        if az aks get-credentials --resource-group "rg-${PROJECT_NAME}-${env}" --name "aks-${PROJECT_NAME}-${env}" --overwrite-existing >/dev/null 2>&1; then
            print_success "Connected to AKS cluster: aks-${PROJECT_NAME}-${env}"
            
            # Remove ArgoCD applications
            if kubectl get namespace argocd >/dev/null 2>&1; then
                print_status "Removing ArgoCD applications..."
                kubectl delete applications --all -n argocd --timeout=300s || true
                kubectl delete namespace argocd --timeout=300s || true
            fi
            
            # Remove platform services
            for namespace in monitoring ai-tools cert-manager; do
                if kubectl get namespace "$namespace" >/dev/null 2>&1; then
                    print_status "Removing namespace: $namespace"
                    kubectl delete namespace "$namespace" --timeout=300s || true
                fi
            done
            
            # Force delete stuck resources
            print_status "Cleaning up persistent volumes..."
            kubectl get pvc --all-namespaces -o json | jq -r '.items[] | "\(.metadata.namespace) \(.metadata.name)"' | while read namespace pvc; do
                kubectl patch pvc "$pvc" -n "$namespace" -p '{"metadata":{"finalizers":null}}' 2>/dev/null || true
                kubectl delete pvc "$pvc" -n "$namespace" --force --grace-period=0 2>/dev/null || true
            done
            
        else
            print_warning "Could not connect to AKS cluster: aks-${PROJECT_NAME}-${env} (may already be deleted)"
        fi
    done
    
    print_success "Kubernetes cleanup completed"
}

# Clean up Terraform infrastructure
cleanup_terraform() {
    print_status "Cleaning up Terraform infrastructure..."
    
    if ! command -v terraform >/dev/null 2>&1; then
        print_warning "Terraform not found, skipping Terraform cleanup"
        return 0
    fi
    
    for env in "${ENVIRONMENTS[@]}"; do
        env_dir="terraform/environments/${env}"
        
        if [ -d "$env_dir" ]; then
            print_status "Destroying $env environment infrastructure..."
            
            cd "$env_dir"
            
            # Initialize Terraform if needed
            if [ ! -d ".terraform" ]; then
                terraform init -input=false || {
                    print_warning "Terraform init failed for $env, skipping"
                    cd - >/dev/null
                    continue
                }
            fi
            
            # Destroy infrastructure
            if [ -f "terraform.tfvars" ]; then
                if [ "$FORCE_CLEANUP" = true ]; then
                    terraform destroy -var-file="terraform.tfvars" -auto-approve -refresh=false || print_warning "Terraform destroy failed for $env"
                else
                    terraform destroy -var-file="terraform.tfvars" -auto-approve || print_warning "Terraform destroy failed for $env"
                fi
            else
                print_warning "No terraform.tfvars found for $env environment"
            fi
            
            # Clean up Terraform files
            rm -f terraform.tfstate*
            rm -f .terraform.lock.hcl
            rm -rf .terraform/
            
            cd - >/dev/null
            print_success "Terraform cleanup completed for $env"
        else
            print_warning "Environment directory not found: $env_dir"
        fi
    done
}

# Clean up Azure resources manually (fallback)
cleanup_azure_resources() {
    print_status "Cleaning up remaining Azure resources..."
    
    for env in "${ENVIRONMENTS[@]}"; do
        rg_name="rg-${PROJECT_NAME}-${env}"
        mc_rg_name="MC_${rg_name}_aks-${PROJECT_NAME}-${env}_eastus"
        
        # Delete main resource group
        if az group show --name "$rg_name" >/dev/null 2>&1; then
            print_status "Deleting resource group: $rg_name"
            az group delete --name "$rg_name" --yes --no-wait
        fi
        
        # Delete managed cluster resource group
        if az group show --name "$mc_rg_name" >/dev/null 2>&1; then
            print_status "Deleting managed cluster resource group: $mc_rg_name"
            az group delete --name "$mc_rg_name" --yes --no-wait
        fi
    done
    
    # Delete Terraform state resource group
    state_rg_name="${PROJECT_NAME}-terraform-state-rg"
    if az group show --name "$state_rg_name" >/dev/null 2>&1; then
        print_status "Deleting Terraform state resource group: $state_rg_name"
        az group delete --name "$state_rg_name" --yes --no-wait
    fi
    
    print_success "Azure resource cleanup initiated"
}

# Clean up service principals
cleanup_service_principals() {
    print_status "Cleaning up service principals..."
    
    # Delete Terraform service principal
    terraform_sp_name="${PROJECT_NAME}-terraform-sp"
    terraform_sp_id=$(az ad sp list --display-name "$terraform_sp_name" --query "[0].appId" -o tsv 2>/dev/null)
    if [ -n "$terraform_sp_id" ] && [ "$terraform_sp_id" != "null" ]; then
        print_status "Deleting service principal: $terraform_sp_name"
        az ad sp delete --id "$terraform_sp_id" || print_warning "Failed to delete service principal: $terraform_sp_name"
    fi
    
    # Delete GitHub Actions service principal
    github_sp_name="${PROJECT_NAME}-github-actions-sp"
    github_sp_id=$(az ad sp list --display-name "$github_sp_name" --query "[0].appId" -o tsv 2>/dev/null)
    if [ -n "$github_sp_id" ] && [ "$github_sp_id" != "null" ]; then
        print_status "Deleting service principal: $github_sp_name"
        az ad sp delete --id "$github_sp_id" || print_warning "Failed to delete service principal: $github_sp_name"
    fi
    
    print_success "Service principal cleanup completed"
}

# Clean up local files
cleanup_local_files() {
    print_status "Cleaning up local configuration files..."
    
    # Remove local credentials
    [ -f ".env" ] && rm -f .env
    [ -f "azure-credentials.json" ] && rm -f azure-credentials.json
    
    # Remove kubectl contexts
    for env in "${ENVIRONMENTS[@]}"; do
        context_name="aks-${PROJECT_NAME}-${env}"
        kubectl config delete-context "$context_name" 2>/dev/null || true
    done
    
    print_success "Local file cleanup completed"
}

# Verify cleanup completion
verify_cleanup() {
    print_status "Verifying cleanup completion..."
    
    # Check for remaining resource groups
    remaining_rgs=$(az group list --query "[?contains(name, '${PROJECT_NAME}')].name" -o tsv 2>/dev/null)
    if [ -n "$remaining_rgs" ]; then
        print_warning "Remaining resource groups found:"
        echo "$remaining_rgs"
    else
        print_success "No remaining resource groups found"
    fi
    
    # Check for remaining service principals
    remaining_sps=$(az ad sp list --display-name "$PROJECT_NAME" --query "[].displayName" -o tsv 2>/dev/null)
    if [ -n "$remaining_sps" ]; then
        print_warning "Remaining service principals found:"
        echo "$remaining_sps"
    else
        print_success "No remaining service principals found"
    fi
    
    # Check for soft-deleted Key Vaults
    deleted_kvs=$(az keyvault list-deleted --query "[?contains(name, '${PROJECT_NAME}')].name" -o tsv 2>/dev/null)
    if [ -n "$deleted_kvs" ]; then
        print_warning "Soft-deleted Key Vaults found (will be purged automatically after 90 days):"
        echo "$deleted_kvs"
        print_status "To purge immediately: az keyvault purge --name <vault-name>"
    fi
}

# Display cleanup summary
display_summary() {
    echo
    print_success "Infrastructure cleanup completed!"
    echo
    print_status "What was cleaned up:"
    echo "  - Kubernetes applications and platform services"
    echo "  - Terraform-managed infrastructure"
    echo "  - Azure resource groups and resources"
    echo "  - Service principals and Azure AD applications"
    echo "  - Local configuration files"
    echo
    print_warning "Important notes:"
    echo "  - Resource deletion may take 10-15 minutes to complete"
    echo "  - Check Azure portal to verify all resources are removed"
    echo "  - Some resources (Key Vault) may be soft-deleted for 90 days"
    echo "  - Review your Azure bill to ensure no unexpected charges"
    echo
    print_status "To verify complete cleanup:"
    echo "  az resource list --query \"[?contains(resourceGroup, '${PROJECT_NAME}')]\" -o table"
    echo "  az group list --query \"[?contains(name, '${PROJECT_NAME}')]\" -o table"
}

# Main execution function
main() {
    parse_arguments "$@"
    
    print_status "Starting infrastructure cleanup for project: $PROJECT_NAME"
    echo
    
    confirm_cleanup
    check_prerequisites
    
    # Execute cleanup steps
    cleanup_kubernetes
    cleanup_terraform
    cleanup_azure_resources
    cleanup_service_principals
    cleanup_local_files
    
    # Wait a moment for Azure operations to propagate
    print_status "Waiting for Azure operations to complete..."
    sleep 10
    
    verify_cleanup
    display_summary
}

# Run main function with all arguments
main "$@"
