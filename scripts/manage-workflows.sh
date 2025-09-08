#!/bin/bash

# GitHub Workflows Management Script
#
# This script helps manage GitHub Actions workflows to prevent unnecessary runs
# and optimize CI/CD pipeline efficiency.

set -e

# ANSI color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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

show_help() {
    echo "GitHub Workflows Management Script"
    echo
    echo "Usage: $0 [COMMAND]"
    echo
    echo "Commands:"
    echo "  status      Show current workflow run status"
    echo "  cancel      Cancel running workflows"
    echo "  list        List all workflows"
    echo "  disable     Disable problematic workflows"
    echo "  enable      Re-enable workflows"
    echo "  help        Show this help message"
    echo
    echo "Examples:"
    echo "  $0 status                    # Show workflow status"
    echo "  $0 cancel                    # Cancel all running workflows"
    echo "  $0 disable drift-detection   # Disable specific workflow"
}

check_prerequisites() {
    if ! command -v gh >/dev/null 2>&1; then
        print_error "GitHub CLI (gh) is not installed"
        exit 1
    fi
    
    if ! gh auth status >/dev/null 2>&1; then
        print_error "Not authenticated with GitHub CLI. Run 'gh auth login'"
        exit 1
    fi
}

show_workflow_status() {
    print_status "Current workflow runs:"
    gh run list --limit 10
    echo
    
    print_status "Running workflows:"
    gh run list --status in_progress --limit 5
}

cancel_running_workflows() {
    print_warning "Cancelling all running workflows..."
    
    # Get running workflow IDs
    running_ids=$(gh run list --status in_progress --json databaseId --jq '.[].databaseId')
    
    if [ -z "$running_ids" ]; then
        print_success "No running workflows to cancel"
        return
    fi
    
    for id in $running_ids; do
        print_status "Cancelling workflow run: $id"
        gh run cancel "$id" || print_warning "Failed to cancel workflow $id"
    done
    
    print_success "Cancelled running workflows"
}

list_workflows() {
    print_status "Available workflows:"
    gh workflow list
}

disable_workflow() {
    local workflow_name="$1"
    
    if [ -z "$workflow_name" ]; then
        print_error "Workflow name required"
        echo "Available workflows:"
        gh workflow list --json name --jq '.[].name'
        return 1
    fi
    
    print_status "Disabling workflow: $workflow_name"
    gh workflow disable "$workflow_name" || print_error "Failed to disable $workflow_name"
    print_success "Disabled workflow: $workflow_name"
}

enable_workflow() {
    local workflow_name="$1"
    
    if [ -z "$workflow_name" ]; then
        print_error "Workflow name required"
        echo "Available workflows:"
        gh workflow list --json name --jq '.[].name'
        return 1
    fi
    
    print_status "Enabling workflow: $workflow_name"
    gh workflow enable "$workflow_name" || print_error "Failed to enable $workflow_name"
    print_success "Enabled workflow: $workflow_name"
}

optimize_workflows() {
    print_status "Optimizing workflow triggers..."
    
    # Cancel any running workflows first
    cancel_running_workflows
    
    # Temporarily disable problematic workflows
    print_status "Temporarily disabling scheduled workflows..."
    disable_workflow "Terraform Drift Detection" || true
    disable_workflow "Cost Monitoring" || true
    
    print_success "Workflow optimization completed"
    print_status "You can re-enable workflows later with: $0 enable <workflow-name>"
}

main() {
    case "${1:-help}" in
        status)
            check_prerequisites
            show_workflow_status
            ;;
        cancel)
            check_prerequisites
            cancel_running_workflows
            ;;
        list)
            check_prerequisites
            list_workflows
            ;;
        disable)
            check_prerequisites
            disable_workflow "$2"
            ;;
        enable)
            check_prerequisites
            enable_workflow "$2"
            ;;
        optimize)
            check_prerequisites
            optimize_workflows
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            print_error "Unknown command: $1"
            show_help
            exit 1
            ;;
    esac
}

main "$@"
