#!/bin/bash

# Fix kubectl Provider Configuration Script
#
# This script automatically fixes the common kubectl provider issue where
# the provider source is incorrectly set to "hashicorp/kubectl" instead of
# "gavinbunney/kubectl".
#
# Usage:
#   ./scripts/fix-kubectl-provider.sh
#   ./scripts/fix-kubectl-provider.sh --check-only

set -e

# ANSI color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
TERRAFORM_FILE="terraform/terraform.tf"
CHECK_ONLY=false

# Utility functions
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
            --check-only)
                CHECK_ONLY=true
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
    echo "kubectl Provider Fix Script"
    echo
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Options:"
    echo "  --check-only    Only check for issues, don't fix them"
    echo "  --help          Show this help message"
    echo
    echo "This script fixes the common kubectl provider configuration issue where"
    echo "the provider source is incorrectly set to 'hashicorp/kubectl' instead of"
    echo "the correct 'gavinbunney/kubectl'."
}

# Check if terraform.tf exists
check_terraform_file() {
    if [[ ! -f "$TERRAFORM_FILE" ]]; then
        print_error "Terraform configuration file not found: $TERRAFORM_FILE"
        exit 1
    fi
    print_success "Found Terraform configuration: $TERRAFORM_FILE"
}

# Check kubectl provider configuration
check_kubectl_provider() {
    print_status "Checking kubectl provider configuration..."
    
    # Check if kubectl provider is declared
    if ! grep -q "kubectl.*=" "$TERRAFORM_FILE"; then
        print_error "kubectl provider not found in $TERRAFORM_FILE"
        print_status "The kubectl provider is required for cert-manager functionality"
        return 1
    fi
    
    # Check if using correct source
    if grep -q "source.*=.*\"gavinbunney/kubectl\"" "$TERRAFORM_FILE"; then
        print_success "kubectl provider is correctly configured (gavinbunney/kubectl)"
        return 0
    elif grep -q "source.*=.*\"hashicorp/kubectl\"" "$TERRAFORM_FILE"; then
        print_warning "kubectl provider is using incorrect source (hashicorp/kubectl)"
        print_status "Should be: gavinbunney/kubectl"
        return 2
    else
        print_error "kubectl provider source not found or malformed"
        return 1
    fi
}

# Check http provider configuration
check_http_provider() {
    print_status "Checking http provider configuration..."
    
    if grep -q "http.*=" "$TERRAFORM_FILE"; then
        print_success "http provider is declared"
        return 0
    else
        print_warning "http provider not found (required for cert-manager CRDs)"
        return 1
    fi
}

# Fix kubectl provider source
fix_kubectl_provider() {
    print_status "Fixing kubectl provider source..."
    
    # Create backup
    cp "$TERRAFORM_FILE" "${TERRAFORM_FILE}.backup"
    print_status "Created backup: ${TERRAFORM_FILE}.backup"
    
    # Fix the provider source
    sed -i.tmp 's/source.*=.*"hashicorp\/kubectl"/source  = "gavinbunney\/kubectl"/' "$TERRAFORM_FILE"
    rm -f "${TERRAFORM_FILE}.tmp"
    
    print_success "Fixed kubectl provider source to use gavinbunney/kubectl"
}

# Add missing http provider
add_http_provider() {
    print_status "Adding missing http provider..."
    
    # Create backup if not already created
    if [[ ! -f "${TERRAFORM_FILE}.backup" ]]; then
        cp "$TERRAFORM_FILE" "${TERRAFORM_FILE}.backup"
        print_status "Created backup: ${TERRAFORM_FILE}.backup"
    fi
    
    # Find the kubectl provider block and add http provider after it
    if grep -q "kubectl.*=" "$TERRAFORM_FILE"; then
        # Add http provider after kubectl
        sed -i.tmp '/kubectl = {/,/}/ {
            /}/ a\
    http = {\
      source  = "hashicorp/http"\
      version = "~> 3.0"\
    }
        }' "$TERRAFORM_FILE"
        rm -f "${TERRAFORM_FILE}.tmp"
        print_success "Added http provider configuration"
    else
        print_error "Could not find kubectl provider block to insert http provider"
        return 1
    fi
}

# Validate terraform configuration
validate_terraform() {
    print_status "Validating Terraform configuration..."
    
    cd terraform
    if terraform validate >/dev/null 2>&1; then
        print_success "Terraform configuration is valid"
        cd ..
        return 0
    else
        print_error "Terraform configuration validation failed"
        print_status "Run 'cd terraform && terraform validate' for details"
        cd ..
        return 1
    fi
}

# Display summary
display_summary() {
    echo
    print_success "kubectl Provider Fix Summary"
    echo
    
    if [[ "$CHECK_ONLY" == true ]]; then
        print_status "Check completed. Use without --check-only to apply fixes."
    else
        print_status "Fixes applied successfully!"
        echo
        print_status "Changes made:"
        echo "  • Fixed kubectl provider source (gavinbunney/kubectl)"
        if [[ -f "${TERRAFORM_FILE}.backup" ]]; then
            echo "  • Created backup: ${TERRAFORM_FILE}.backup"
        fi
        echo
        print_status "Next steps:"
        echo "  1. Review changes: git diff $TERRAFORM_FILE"
        echo "  2. Test Terraform: cd terraform && terraform init"
        echo "  3. Commit changes: git add $TERRAFORM_FILE && git commit -m 'fix: correct kubectl provider source'"
    fi
}

# Main execution function
main() {
    parse_arguments "$@"
    
    print_status "kubectl Provider Configuration Fix"
    echo
    
    # Check terraform file exists
    check_terraform_file
    
    # Check current configuration
    local kubectl_status
    check_kubectl_provider
    kubectl_status=$?
    
    local http_status
    check_http_provider
    http_status=$?
    
    # If check-only mode, just report and exit
    if [[ "$CHECK_ONLY" == true ]]; then
        echo
        if [[ $kubectl_status -eq 0 && $http_status -eq 0 ]]; then
            print_success "All provider configurations are correct"
        else
            print_warning "Provider configuration issues found"
            if [[ $kubectl_status -eq 2 ]]; then
                echo "  • kubectl provider uses wrong source (hashicorp instead of gavinbunney)"
            fi
            if [[ $http_status -ne 0 ]]; then
                echo "  • http provider is missing"
            fi
        fi
        display_summary
        exit 0
    fi
    
    # Apply fixes if needed
    local changes_made=false
    
    if [[ $kubectl_status -eq 2 ]]; then
        fix_kubectl_provider
        changes_made=true
    fi
    
    if [[ $http_status -ne 0 ]]; then
        add_http_provider
        changes_made=true
    fi
    
    if [[ "$changes_made" == true ]]; then
        # Validate the changes
        validate_terraform
        display_summary
    else
        print_success "No fixes needed - configuration is already correct"
    fi
}

# Run main function with all arguments
main "$@"
