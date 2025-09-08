#!/bin/bash

# Infrastructure Overview Script - Shell Wrapper
#
# This script provides a convenient wrapper around the Python infrastructure
# overview script with common usage patterns and environment detection.
#
# Usage:
#   ./scripts/show-infrastructure.sh [options]
#   ./scripts/show-infrastructure.sh --help
#   ./scripts/show-infrastructure.sh --env dev
#   ./scripts/show-infrastructure.sh --all --costs

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Default values
PROJECT_NAME="aks-platform"
ENVIRONMENT=""
ALL_ENVIRONMENTS=false
INCLUDE_COSTS=false
OUTPUT_FORMAT="text"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print functions
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

# Show usage information
show_usage() {
    cat << EOF
Infrastructure Overview Script

USAGE:
    $0 [OPTIONS]

OPTIONS:
    -h, --help              Show this help message
    -p, --project-name NAME Project name (default: aks-platform)
    -e, --env ENVIRONMENT   Show specific environment only (dev, staging, prod)
    -a, --all               Show all environments
    -c, --costs             Include cost information
    -f, --format FORMAT     Output format: text, json (default: text)
    
EXAMPLES:
    # Show dev environment only (default)
    $0
    
    # Show specific environment
    $0 --env staging
    
    # Show all environments with costs
    $0 --all --costs
    
    # Show infrastructure for custom project
    $0 --project-name my-project --all

PREREQUISITES:
    - Azure CLI installed and authenticated
    - Python 3.7+ with virtual environment
    - Required Python packages (see scripts/requirements.txt)

EOF
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            -p|--project-name)
                PROJECT_NAME="$2"
                shift 2
                ;;
            -e|--env|--environment)
                ENVIRONMENT="$2"
                shift 2
                ;;
            -a|--all|--all-environments)
                ALL_ENVIRONMENTS=true
                shift
                ;;
            -c|--costs|--include-costs)
                INCLUDE_COSTS=true
                shift
                ;;
            -f|--format|--output-format)
                OUTPUT_FORMAT="$2"
                shift 2
                ;;
            *)
                print_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
}

# Check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    # Check if we're in the right directory
    if [[ ! -f "$PROJECT_ROOT/terraform/main.tf" ]]; then
        print_error "This script must be run from the project root directory"
        print_error "Expected to find terraform/main.tf"
        exit 1
    fi
    
    # Check Azure CLI
    if ! command -v az &> /dev/null; then
        print_error "Azure CLI is not installed or not in PATH"
        print_error "Please install Azure CLI: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check Azure CLI authentication
    if ! az account show &> /dev/null; then
        print_error "Azure CLI is not authenticated"
        print_error "Please run: az login"
        exit 1
    fi
    
    # Check Python
    if ! command -v python3 &> /dev/null; then
        print_error "Python 3 is not installed or not in PATH"
        exit 1
    fi
    
    # Check if virtual environment exists
    if [[ -d "$PROJECT_ROOT/venv" ]]; then
        print_status "Using virtual environment: $PROJECT_ROOT/venv"
    else
        print_warning "Virtual environment not found at $PROJECT_ROOT/venv"
        print_warning "Consider running: python3 -m venv venv && source venv/bin/activate"
    fi
    
    print_success "Prerequisites check passed"
}

# Build Python command arguments
build_python_args() {
    local args=()
    
    args+=("--project-name" "$PROJECT_NAME")
    
    if [[ -n "$ENVIRONMENT" ]]; then
        args+=("--environment" "$ENVIRONMENT")
    fi
    
    if [[ "$ALL_ENVIRONMENTS" == true ]]; then
        args+=("--all-environments")
    fi
    
    if [[ "$INCLUDE_COSTS" == true ]]; then
        args+=("--include-costs")
    fi
    
    args+=("--output-format" "$OUTPUT_FORMAT")
    
    echo "${args[@]}"
}

# Main execution
main() {
    parse_arguments "$@"
    
    print_status "Starting infrastructure overview for project: $PROJECT_NAME"
    echo
    
    check_prerequisites
    echo
    
    # Change to project root
    cd "$PROJECT_ROOT"
    
    # Build Python command
    local python_args
    python_args=($(build_python_args))
    
    # Activate virtual environment if it exists
    if [[ -d "venv" ]]; then
        print_status "Activating virtual environment..."
        source venv/bin/activate
    fi
    
    # Run the Python script
    print_status "Executing infrastructure overview..."
    echo
    
    python3 scripts/show-infrastructure.py "${python_args[@]}"
    
    echo
    print_success "Infrastructure overview completed!"
}

# Run main function with all arguments
main "$@"
