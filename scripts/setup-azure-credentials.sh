#!/bin/bash

# Azure Credentials Setup - Simple Wrapper
#
# This is a lightweight wrapper around the Python setup script that provides
# a simple command-line interface for Azure credentials and infrastructure setup.
#
# The wrapper handles:
# 1. Dependency checking and installation
# 2. User-friendly error messages
# 3. Cross-platform compatibility
# 4. Simple command-line interface
#
# Usage:
#   ./scripts/setup-azure-credentials.sh [OPTIONS]
#   ./scripts/setup-azure-credentials.sh --project-name "my-project" --location "East US 2"

set -e

# Source virtual environment utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/venv-utils.sh"

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if Python script exists
check_python_script() {
    local script_path="$(dirname "$0")/setup-azure-credentials.py"
    
    if [[ ! -f "$script_path" ]]; then
        print_error "Python setup script not found: $script_path"
        exit 1
    fi
    
    echo "$script_path"
}

# Check Python installation
check_python() {
    if ! command -v python3 >/dev/null 2>&1; then
        print_error "Python 3 is not installed"
        print_status "Please install Python 3.7+ and try again"
        exit 1
    fi
    
    # Check Python version
    local python_version=$(python3 -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
    local major=$(echo "$python_version" | cut -d. -f1)
    local minor=$(echo "$python_version" | cut -d. -f2)
    
    if [[ $major -lt 3 ]] || [[ $major -eq 3 && $minor -lt 7 ]]; then
        print_error "Python 3.7+ is required (found: $python_version)"
        exit 1
    fi
    
    print_success "Python $python_version found"
}

# Check Azure CLI
check_azure_cli() {
    if ! command -v az >/dev/null 2>&1; then
        print_error "Azure CLI is not installed"
        print_status "Install with: curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash"
        exit 1
    fi
    
    # Check if logged in
    if ! az account show >/dev/null 2>&1; then
        print_warning "Not logged in to Azure"
        print_status "Please run 'az login' first"
        exit 1
    fi
    
    print_success "Azure CLI is ready"
}

# Install Python dependencies with virtual environment support
install_dependencies() {
    print_status "Checking Python dependencies..."

    # Check virtual environment status
    check_virtual_environment

    # Check if packages are already installed
    if python3 -c "import azure.identity, azure.mgmt.storage, azure.mgmt.authorization" >/dev/null 2>&1; then
        print_success "All Python dependencies are installed"
        return 0
    fi

    # Use enhanced dependency installation
    local req_file="$(dirname "$0")/requirements.txt"
    local fallback_packages=("azure-identity" "azure-mgmt-storage" "azure-mgmt-authorization")

    install_dependencies_enhanced "$req_file" "${fallback_packages[@]}"
}

# Show help
show_help() {
    echo "Azure Credentials Setup - Simple Wrapper"
    echo
    echo "This script sets up Azure service principals, storage accounts, and"
    echo "Terraform backend configuration for the AKS GitOps platform."
    echo
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Options:"
    echo "  --project-name NAME      Project name (default: aks-platform)"
    echo "  --location LOCATION      Azure region (default: East US)"
    echo "  --environment ENV        Single environment to setup (default: dev)"
    echo "  --all-environments       Setup all environments (dev, staging, prod)"
    echo "  --install-deps           Install Python dependencies automatically"
    echo "  --help                   Show this help message"
    echo
    echo "Environment Isolation:"
    echo "  Environment must be explicitly specified for security."
    echo "  No default environment to prevent accidental resource creation."
    echo "  Use --all-environments only if you have permissions for all environments."
    echo
    echo "Examples:"
    echo "  $0 --environment dev                 # Setup dev environment only"
    echo "  $0 --environment staging             # Setup staging environment only"
    echo "  $0 --environment prod                # Setup prod environment only"
    echo "  $0 --all-environments                # Setup all environments (requires broad permissions)"
    echo "  $0 --environment dev --project-name my-project    # Custom project name"
    echo "  $0 --environment dev --location 'East US 2'       # Custom location"
    echo "  $0 --install-deps                    # Auto-install dependencies"
    echo
    echo "Prerequisites:"
    echo "  - Python 3.7+"
    echo "  - Azure CLI (logged in)"
    echo "  - Azure subscription with appropriate permissions"
}

# Main function
main() {
    local install_deps=false
    local python_args=()
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --install-deps)
                install_deps=true
                shift
                ;;
            --help)
                show_help
                exit 0
                ;;
            *)
                # Pass through to Python script
                python_args+=("$1")
                shift
                ;;
        esac
    done
    
    print_status "Azure Credentials Setup"
    echo

    # Check if environment is specified (basic validation)
    local has_env_arg=false
    for arg in "${python_args[@]}"; do
        if [[ "$arg" == "--environment" || "$arg" == "--environments" || "$arg" == "--all-environments" ]]; then
            has_env_arg=true
            break
        fi
    done

    if [[ "$has_env_arg" == "false" ]]; then
        print_error "Environment must be specified explicitly for security."
        print_error "Use one of:"
        print_error "  $0 --environment dev                 # Setup single environment"
        print_error "  $0 --environment staging             # Setup single environment"
        print_error "  $0 --environment prod                # Setup single environment"
        print_error "  $0 --all-environments                # Setup all environments"
        print_error ""
        print_error "This prevents accidentally creating resources in unintended environments."
        exit 1
    fi

    # Check prerequisites
    check_python
    check_azure_cli

    # Install dependencies if requested
    if [[ "$install_deps" == "true" ]]; then
        install_dependencies
    fi
    
    # Get Python script path
    local python_script=$(check_python_script)
    
    # Run Python script with arguments
    print_status "Running Azure credentials setup..."
    python3 "$python_script" "${python_args[@]}"
    
    local exit_code=$?
    
    if [[ $exit_code -eq 0 ]]; then
        echo
        print_success "Azure credentials setup completed successfully!"
        print_status "You can now proceed with infrastructure deployment"
    else
        echo
        print_error "Setup failed with exit code: $exit_code"
        print_status "Check the error messages above for details"
        exit $exit_code
    fi
}

# Run main function
main "$@"
