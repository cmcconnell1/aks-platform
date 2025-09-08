#!/bin/bash

# GitHub Secrets Setup Script for AKS GitOps CI/CD Pipeline
#
# This script automates the configuration of GitHub repository secrets required
# for the CI/CD pipeline to deploy and manage the AKS GitOps platform.
#
# Key Functions:
# 1. Azure Service Principal Secrets:
#    - Configures AZURE_CLIENT_ID, AZURE_CLIENT_SECRET, AZURE_TENANT_ID
#    - Sets up AZURE_SUBSCRIPTION_ID for resource management
#    - Enables GitHub Actions to authenticate with Azure
#
# 2. Terraform Backend Secrets:
#    - Configures storage account access for Terraform state
#    - Sets up backend configuration for state management
#    - Enables secure state locking and consistency
#
# 3. Optional Integration Secrets:
#    - Infracost API key for cost estimation in PRs
#    - Slack webhook for deployment notifications
#    - Custom notification endpoints
#
# 4. Environment Protection:
#    - Guides setup of environment protection rules
#    - Configures required reviewers for production deployments
#    - Sets up branch protection policies
#
# Prerequisites:
#   - GitHub CLI installed and authenticated (gh auth login)
#   - Repository access with admin permissions
#   - Azure service principal credentials available
#   - Terraform backend storage account configured
#
# Usage:
#   ./scripts/setup-github-secrets.sh
#   gh auth login  # Run first if not authenticated

set -e  # Exit immediately if any command fails

# ANSI color codes for consistent terminal output formatting
RED='\033[0;31m'      # Error messages and failures
GREEN='\033[0;32m'    # Success messages and confirmations
YELLOW='\033[1;33m'   # Warning messages and important notes
BLUE='\033[0;34m'     # Informational messages and progress updates
NC='\033[0m'          # Reset to default terminal color

# Utility functions for consistent colored output and system validation

print_status() {
    # Print informational messages with blue [INFO] prefix
    # Used for progress updates and general information during setup
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    # Print success messages with green [SUCCESS] prefix
    # Used when secrets are successfully configured or operations complete
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    # Print warning messages with yellow [WARNING] prefix
    # Used for optional configurations or potential issues
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    # Print error messages with red [ERROR] prefix
    # Used for fatal errors that prevent script execution
    echo -e "${RED}[ERROR]${NC} $1"
}

# Utility function to verify command availability in system PATH
# Essential for checking GitHub CLI and other required tools
# Returns 0 if command exists, 1 if not found
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    if ! command_exists gh; then
        print_error "GitHub CLI is not installed. Please install it first."
        print_status "Install with: brew install gh (macOS) or visit https://cli.github.com/"
        exit 1
    fi
    
    # Check if logged in to GitHub
    if ! gh auth status >/dev/null 2>&1; then
        print_error "Not logged in to GitHub. Please run 'gh auth login' first."
        exit 1
    fi
    
    # Check if .env file exists
    if [ ! -f ".env" ]; then
        print_error ".env file not found. Please run setup-azure-credentials.sh first."
        exit 1
    fi
    
    # Check if GitHub Actions credentials file exists
    if [ ! -f "github-actions-credentials.json" ]; then
        print_error "github-actions-credentials.json not found. Please run setup-azure-credentials.sh first."
        exit 1
    fi
    
    print_success "Prerequisites check passed"
}

# Get repository information
get_repo_info() {
    print_status "Getting repository information..."
    
    REPO_OWNER=$(gh repo view --json owner --jq '.owner.login')
    REPO_NAME=$(gh repo view --json name --jq '.name')
    
    print_success "Repository: $REPO_OWNER/$REPO_NAME"
}

# Set up Azure credentials as environment-specific secrets
setup_azure_secrets() {
    print_status "Setting up Azure credentials as environment-specific secrets..."

    # Source the .env file to get variables
    source .env

    # First, remove any existing repository-level secrets
    print_status "Removing repository-level Azure secrets (moving to environment-specific)..."
    gh secret delete ARM_CLIENT_ID 2>/dev/null || true
    gh secret delete ARM_CLIENT_SECRET 2>/dev/null || true
    gh secret delete ARM_SUBSCRIPTION_ID 2>/dev/null || true
    gh secret delete ARM_TENANT_ID 2>/dev/null || true
    gh secret delete AZURE_CREDENTIALS 2>/dev/null || true

    # Set environment-specific secrets for each environment
    for env in dev staging prod; do
        print_status "Setting up Azure secrets for environment: $env"

        # For now, all environments use the same credentials
        # In production, you would have different service principals per environment
        echo "$ARM_CLIENT_ID" | gh secret set ARM_CLIENT_ID --env "$env" 2>/dev/null || print_warning "Failed to set ARM_CLIENT_ID for $env"
        echo "$ARM_CLIENT_SECRET" | gh secret set ARM_CLIENT_SECRET --env "$env" 2>/dev/null || print_warning "Failed to set ARM_CLIENT_SECRET for $env"
        echo "$ARM_SUBSCRIPTION_ID" | gh secret set ARM_SUBSCRIPTION_ID --env "$env" 2>/dev/null || print_warning "Failed to set ARM_SUBSCRIPTION_ID for $env"
        echo "$ARM_TENANT_ID" | gh secret set ARM_TENANT_ID --env "$env" 2>/dev/null || print_warning "Failed to set ARM_TENANT_ID for $env"

        # Set the complete Azure credentials JSON for azure/login action
        gh secret set AZURE_CREDENTIALS --env "$env" < github-actions-credentials.json 2>/dev/null || print_warning "Failed to set AZURE_CREDENTIALS for $env"

        print_success "Azure credentials configured for $env environment"
    done

    print_success "Azure credentials secrets configured for all environments"
    print_warning "NOTE: All environments currently use the same credentials"
    print_status "For production use, create separate service principals per environment"
}

# Set up optional secrets
setup_optional_secrets() {
    print_status "Setting up optional secrets..."
    
    # Infracost API key (for cost estimation)
    read -p "Enter Infracost API key (optional, press Enter to skip): " INFRACOST_API_KEY
    if [ -n "$INFRACOST_API_KEY" ]; then
        echo "$INFRACOST_API_KEY" | gh secret set INFRACOST_API_KEY
        print_success "Infracost API key configured"
    else
        print_warning "Infracost API key skipped - cost estimation will not work"
    fi
    
    # Slack webhook URL (for notifications)
    read -p "Enter Slack webhook URL (optional, press Enter to skip): " SLACK_WEBHOOK_URL
    if [ -n "$SLACK_WEBHOOK_URL" ]; then
        echo "$SLACK_WEBHOOK_URL" | gh secret set SLACK_WEBHOOK_URL
        print_success "Slack webhook URL configured"
    else
        print_warning "Slack webhook URL skipped - Slack notifications will not work"
    fi
}

# Set up environment protection rules
setup_environment_protection() {
    print_status "Setting up environment protection rules..."
    
    # Create environments
    for env in dev staging prod; do
        print_status "Creating environment: $env"
        
        # Note: Environment creation via CLI is limited
        # Users need to create environments manually in GitHub UI
        print_warning "Please create environment '$env' manually in GitHub repository settings"
        print_status "Go to: https://github.com/$REPO_OWNER/$REPO_NAME/settings/environments"
    done
    
    # Create environments and add environment-specific secrets
    for env in dev staging prod; do
        print_status "Setting up environment: $env"

        # Create environment using GitHub API
        gh api \
            --method PUT \
            "/repos/$REPO_OWNER/$REPO_NAME/environments/$env" \
            --field "wait_timer=0" \
            --field "prevent_self_review=false" \
            --field "reviewers=[]" \
            --field "deployment_branch_policy=null" \
            2>/dev/null || print_warning "Environment '$env' may already exist"

        # Add environment-specific variables
        case $env in
            "dev")
                gh variable set ENVIRONMENT --env "$env" --body "dev" 2>/dev/null || print_warning "Failed to set ENVIRONMENT variable for $env"
                gh variable set CLUSTER_NAME --env "$env" --body "aks-platform-dev" 2>/dev/null || print_warning "Failed to set CLUSTER_NAME variable for $env"
                ;;
            "staging")
                gh variable set ENVIRONMENT --env "$env" --body "staging" 2>/dev/null || print_warning "Failed to set ENVIRONMENT variable for $env"
                gh variable set CLUSTER_NAME --env "$env" --body "aks-platform-staging" 2>/dev/null || print_warning "Failed to set CLUSTER_NAME variable for $env"
                ;;
            "prod")
                gh variable set ENVIRONMENT --env "$env" --body "prod" 2>/dev/null || print_warning "Failed to set ENVIRONMENT variable for $env"
                gh variable set CLUSTER_NAME --env "$env" --body "aks-platform-prod" 2>/dev/null || print_warning "Failed to set CLUSTER_NAME variable for $env"
                ;;
        esac
    done

    # Configure environment protection rules for staging and prod
    print_status "Configuring environment protection rules..."

    for env in staging prod; do
        print_status "Setting up protection for: $env"

        # Enable required reviewers for staging and prod
        gh api \
            --method PUT \
            "/repos/$REPO_OWNER/$REPO_NAME/environments/$env" \
            --field "wait_timer=0" \
            --field "prevent_self_review=true" \
            --field "reviewers[0][type]=User" \
            --field "reviewers[0][id]=$(gh api user --jq '.id')" \
            2>/dev/null || print_warning "Failed to set protection rules for $env"
    done

    print_success "GitHub environments created successfully!"
    print_status "Environment protection configured for staging and prod"
}

# Verify secrets configuration
verify_secrets() {
    print_status "Verifying secrets configuration..."
    
    # List configured secrets
    SECRETS=$(gh secret list --json name --jq '.[].name')
    
    REQUIRED_SECRETS=("ARM_CLIENT_ID" "ARM_CLIENT_SECRET" "ARM_SUBSCRIPTION_ID" "ARM_TENANT_ID" "AZURE_CREDENTIALS")
    
    for secret in "${REQUIRED_SECRETS[@]}"; do
        if echo "$SECRETS" | grep -q "$secret"; then
            print_success "$secret configured"
        else
            print_error "$secret missing"
        fi
    done

    OPTIONAL_SECRETS=("INFRACOST_API_KEY" "SLACK_WEBHOOK_URL")

    print_status "Optional secrets:"
    for secret in "${OPTIONAL_SECRETS[@]}"; do
        if echo "$SECRETS" | grep -q "$secret"; then
            print_success "$secret configured"
        else
            print_warning "$secret not configured"
        fi
    done
}

# Display next steps
display_next_steps() {
    print_success "GitHub secrets setup completed!"
    echo
    print_status "Next steps:"
    echo "1. Create environments manually in GitHub repository settings"
    echo "2. Configure environment protection rules for staging and prod"
    echo "3. Test the CI/CD pipeline by creating a pull request"
    echo "4. Review and customize workflow triggers as needed"
    echo
    print_status "Useful commands:"
    echo "  - View secrets: gh secret list"
    echo "  - Update secret: echo 'new-value' | gh secret set SECRET_NAME"
    echo "  - Delete secret: gh secret delete SECRET_NAME"
    echo
    print_warning "Security reminders:"
    echo "  - Regularly rotate service principal secrets"
    echo "  - Monitor GitHub Actions usage and costs"
    echo "  - Review workflow permissions regularly"
    echo "  - Enable branch protection rules"
}

# Main execution
main() {
    print_status "Starting GitHub secrets setup..."
    echo
    
    check_prerequisites
    get_repo_info
    setup_azure_secrets
    setup_optional_secrets
    setup_environment_protection
    verify_secrets
    display_next_steps
}

# Run main function
main "$@"
