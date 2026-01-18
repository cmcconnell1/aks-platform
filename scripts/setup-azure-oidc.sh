#!/bin/bash

# Azure to GitHub OIDC Federation Setup Script
#
# This script configures workload identity federation between Azure and GitHub Actions,
# enabling secure authentication without storing long-lived secrets.
#
# OIDC Benefits:
# - Short-lived tokens (automatically expire)
# - No secrets to rotate (Azure issues tokens on-demand)
# - Federated identity (GitHub vouches for the workflow)
# - Scoped access (tokens are limited to specific repos/branches)
#
# Prerequisites:
#   - Azure CLI installed and logged in (az login)
#   - GitHub CLI installed and authenticated (gh auth login)
#   - Owner/Contributor access on Azure subscription
#   - Admin access to GitHub repository
#
# Usage:
#   ./scripts/setup-azure-oidc.sh
#   ./scripts/setup-azure-oidc.sh --environment prod
#   ./scripts/setup-azure-oidc.sh --app-name my-app --subscription-id xxx

set -e

# =============================================================================
# Configuration
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Default values
DEFAULT_APP_NAME="aks-platform-github-oidc"
DEFAULT_LOCATION="eastus"

# ANSI color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# =============================================================================
# Utility Functions
# =============================================================================

print_header() {
    echo -e "\n${CYAN}============================================================${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${CYAN}============================================================${NC}\n"
}

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

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# =============================================================================
# Argument Parsing
# =============================================================================

APP_NAME=""
SUBSCRIPTION_ID=""
ENVIRONMENT=""
GITHUB_ORG=""
GITHUB_REPO=""
DRY_RUN=false

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --app-name)
                APP_NAME="$2"
                shift 2
                ;;
            --subscription-id)
                SUBSCRIPTION_ID="$2"
                shift 2
                ;;
            --environment)
                ENVIRONMENT="$2"
                shift 2
                ;;
            --github-org)
                GITHUB_ORG="$2"
                shift 2
                ;;
            --github-repo)
                GITHUB_REPO="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --help|-h)
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

show_help() {
    cat << EOF
Azure to GitHub OIDC Federation Setup

Usage: $0 [OPTIONS]

Options:
    --app-name NAME         Azure AD application name (default: $DEFAULT_APP_NAME)
    --subscription-id ID    Azure subscription ID (default: current subscription)
    --environment ENV       Target environment (dev, staging, prod, or 'all')
    --github-org ORG        GitHub organization/owner (default: detected from git)
    --github-repo REPO      GitHub repository name (default: detected from git)
    --dry-run               Show what would be done without making changes
    --help, -h              Show this help message

Examples:
    $0                                          # Interactive setup
    $0 --environment dev                        # Setup for dev environment only
    $0 --environment all                        # Setup for all environments
    $0 --app-name my-app --subscription-id xxx  # Custom app name and subscription

For more information, see docs/azure-github-oidc-setup.md
EOF
}

# =============================================================================
# Prerequisite Checks
# =============================================================================

check_prerequisites() {
    print_header "Checking Prerequisites"

    local errors=0

    # Check Azure CLI
    if ! command_exists az; then
        print_error "Azure CLI is not installed"
        print_status "Install with: brew install azure-cli (macOS) or see https://aka.ms/installazurecli"
        ((errors++))
    else
        print_success "Azure CLI is installed"
    fi

    # Check GitHub CLI
    if ! command_exists gh; then
        print_error "GitHub CLI is not installed"
        print_status "Install with: brew install gh (macOS) or see https://cli.github.com/"
        ((errors++))
    else
        print_success "GitHub CLI is installed"
    fi

    # Check jq
    if ! command_exists jq; then
        print_error "jq is not installed"
        print_status "Install with: brew install jq (macOS) or apt-get install jq (Linux)"
        ((errors++))
    else
        print_success "jq is installed"
    fi

    # Check Azure login
    if ! az account show >/dev/null 2>&1; then
        print_error "Not logged in to Azure. Please run 'az login' first."
        ((errors++))
    else
        print_success "Azure CLI is authenticated"
    fi

    # Check GitHub login
    if ! gh auth status >/dev/null 2>&1; then
        print_error "Not logged in to GitHub. Please run 'gh auth login' first."
        ((errors++))
    else
        print_success "GitHub CLI is authenticated"
    fi

    if [ $errors -gt 0 ]; then
        print_error "Prerequisites check failed with $errors error(s)"
        exit 1
    fi

    print_success "All prerequisites met"
}

# =============================================================================
# Azure Configuration Detection
# =============================================================================

detect_azure_config() {
    print_header "Detecting Azure Configuration"

    # Get subscription ID if not provided
    if [ -z "$SUBSCRIPTION_ID" ]; then
        SUBSCRIPTION_ID=$(az account show --query id -o tsv)
        print_status "Using current subscription: $SUBSCRIPTION_ID"
    fi

    # Get tenant ID
    TENANT_ID=$(az account show --query tenantId -o tsv)
    print_status "Tenant ID: $TENANT_ID"

    # Get subscription name
    SUBSCRIPTION_NAME=$(az account show --query name -o tsv)
    print_status "Subscription: $SUBSCRIPTION_NAME"

    # Set app name if not provided
    if [ -z "$APP_NAME" ]; then
        APP_NAME="$DEFAULT_APP_NAME"
    fi
    print_status "Application name: $APP_NAME"
}

# =============================================================================
# GitHub Configuration Detection
# =============================================================================

detect_github_config() {
    print_header "Detecting GitHub Configuration"

    # Try to detect from git remote if not provided
    if [ -z "$GITHUB_ORG" ] || [ -z "$GITHUB_REPO" ]; then
        if git remote get-url origin >/dev/null 2>&1; then
            REMOTE_URL=$(git remote get-url origin)

            # Parse GitHub org and repo from URL
            if [[ "$REMOTE_URL" =~ github\.com[:/]([^/]+)/([^/]+)(\.git)?$ ]]; then
                GITHUB_ORG="${GITHUB_ORG:-${BASH_REMATCH[1]}}"
                GITHUB_REPO="${GITHUB_REPO:-${BASH_REMATCH[2]%.git}}"
            fi
        fi
    fi

    # Fallback to gh repo view if still not detected
    if [ -z "$GITHUB_ORG" ]; then
        GITHUB_ORG=$(gh repo view --json owner --jq '.owner.login' 2>/dev/null || echo "")
    fi
    if [ -z "$GITHUB_REPO" ]; then
        GITHUB_REPO=$(gh repo view --json name --jq '.name' 2>/dev/null || echo "")
    fi

    if [ -z "$GITHUB_ORG" ] || [ -z "$GITHUB_REPO" ]; then
        print_error "Could not detect GitHub repository"
        print_status "Please provide --github-org and --github-repo options"
        exit 1
    fi

    print_status "GitHub Organization: $GITHUB_ORG"
    print_status "GitHub Repository: $GITHUB_REPO"

    GITHUB_REPO_FULL="$GITHUB_ORG/$GITHUB_REPO"
}

# =============================================================================
# Azure AD Application Setup
# =============================================================================

create_azure_app() {
    print_header "Creating Azure AD Application"

    # Check if app already exists
    EXISTING_APP_ID=$(az ad app list --display-name "$APP_NAME" --query "[0].appId" -o tsv 2>/dev/null || echo "")

    if [ -n "$EXISTING_APP_ID" ] && [ "$EXISTING_APP_ID" != "null" ]; then
        print_warning "Application '$APP_NAME' already exists (App ID: $EXISTING_APP_ID)"
        read -p "Do you want to use the existing application? (y/n): " USE_EXISTING
        if [[ "$USE_EXISTING" =~ ^[Yy]$ ]]; then
            APP_ID="$EXISTING_APP_ID"
            print_status "Using existing application"
        else
            print_error "Please delete the existing application or use a different name"
            exit 1
        fi
    else
        if [ "$DRY_RUN" = true ]; then
            print_status "[DRY RUN] Would create Azure AD application: $APP_NAME"
            APP_ID="dry-run-app-id"
        else
            print_status "Creating Azure AD application: $APP_NAME"
            APP_ID=$(az ad app create \
                --display-name "$APP_NAME" \
                --query appId -o tsv)
            print_success "Created application with App ID: $APP_ID"
        fi
    fi

    # Create service principal if it doesn't exist
    EXISTING_SP=$(az ad sp show --id "$APP_ID" 2>/dev/null || echo "")

    if [ -z "$EXISTING_SP" ]; then
        if [ "$DRY_RUN" = true ]; then
            print_status "[DRY RUN] Would create service principal for app: $APP_ID"
            SP_OBJECT_ID="dry-run-sp-object-id"
        else
            print_status "Creating service principal..."
            SP_OBJECT_ID=$(az ad sp create --id "$APP_ID" --query id -o tsv)
            print_success "Created service principal with Object ID: $SP_OBJECT_ID"
        fi
    else
        SP_OBJECT_ID=$(az ad sp show --id "$APP_ID" --query id -o tsv)
        print_status "Using existing service principal: $SP_OBJECT_ID"
    fi
}

# =============================================================================
# Federated Credentials Setup
# =============================================================================

create_federated_credentials() {
    print_header "Creating Federated Credentials"

    # Determine which environments to configure
    local ENVIRONMENTS=()
    if [ -n "$ENVIRONMENT" ]; then
        if [ "$ENVIRONMENT" = "all" ]; then
            ENVIRONMENTS=("dev" "staging" "prod")
        else
            ENVIRONMENTS=("$ENVIRONMENT")
        fi
    else
        # Default to all environments
        ENVIRONMENTS=("dev" "staging" "prod")
    fi

    # Also add a credential for the main branch (for PR workflows)
    create_branch_credential "main"

    # Create environment-specific credentials
    for env in "${ENVIRONMENTS[@]}"; do
        create_environment_credential "$env"
    done

    # Create credential for pull requests
    create_pr_credential
}

create_branch_credential() {
    local BRANCH="$1"
    local CREDENTIAL_NAME="github-${GITHUB_REPO}-branch-${BRANCH}"
    local SUBJECT="repo:${GITHUB_REPO_FULL}:ref:refs/heads/${BRANCH}"

    print_status "Creating federated credential for branch: $BRANCH"

    if [ "$DRY_RUN" = true ]; then
        print_status "[DRY RUN] Would create credential: $CREDENTIAL_NAME"
        print_status "[DRY RUN] Subject: $SUBJECT"
        return
    fi

    # Check if credential already exists
    EXISTING=$(az ad app federated-credential list --id "$APP_ID" --query "[?name=='$CREDENTIAL_NAME'].name" -o tsv 2>/dev/null || echo "")

    if [ -n "$EXISTING" ]; then
        print_warning "Credential '$CREDENTIAL_NAME' already exists, updating..."
        az ad app federated-credential delete --id "$APP_ID" --federated-credential-id "$CREDENTIAL_NAME" 2>/dev/null || true
    fi

    az ad app federated-credential create \
        --id "$APP_ID" \
        --parameters "{
            \"name\": \"$CREDENTIAL_NAME\",
            \"issuer\": \"https://token.actions.githubusercontent.com\",
            \"subject\": \"$SUBJECT\",
            \"description\": \"GitHub Actions for $GITHUB_REPO_FULL branch $BRANCH\",
            \"audiences\": [\"api://AzureADTokenExchange\"]
        }" >/dev/null

    print_success "Created federated credential for branch: $BRANCH"
}

create_environment_credential() {
    local ENV="$1"
    local CREDENTIAL_NAME="github-${GITHUB_REPO}-env-${ENV}"
    local SUBJECT="repo:${GITHUB_REPO_FULL}:environment:${ENV}"

    print_status "Creating federated credential for environment: $ENV"

    if [ "$DRY_RUN" = true ]; then
        print_status "[DRY RUN] Would create credential: $CREDENTIAL_NAME"
        print_status "[DRY RUN] Subject: $SUBJECT"
        return
    fi

    # Check if credential already exists
    EXISTING=$(az ad app federated-credential list --id "$APP_ID" --query "[?name=='$CREDENTIAL_NAME'].name" -o tsv 2>/dev/null || echo "")

    if [ -n "$EXISTING" ]; then
        print_warning "Credential '$CREDENTIAL_NAME' already exists, updating..."
        az ad app federated-credential delete --id "$APP_ID" --federated-credential-id "$CREDENTIAL_NAME" 2>/dev/null || true
    fi

    az ad app federated-credential create \
        --id "$APP_ID" \
        --parameters "{
            \"name\": \"$CREDENTIAL_NAME\",
            \"issuer\": \"https://token.actions.githubusercontent.com\",
            \"subject\": \"$SUBJECT\",
            \"description\": \"GitHub Actions for $GITHUB_REPO_FULL environment $ENV\",
            \"audiences\": [\"api://AzureADTokenExchange\"]
        }" >/dev/null

    print_success "Created federated credential for environment: $ENV"
}

create_pr_credential() {
    local CREDENTIAL_NAME="github-${GITHUB_REPO}-pr"
    local SUBJECT="repo:${GITHUB_REPO_FULL}:pull_request"

    print_status "Creating federated credential for pull requests"

    if [ "$DRY_RUN" = true ]; then
        print_status "[DRY RUN] Would create credential: $CREDENTIAL_NAME"
        print_status "[DRY RUN] Subject: $SUBJECT"
        return
    fi

    # Check if credential already exists
    EXISTING=$(az ad app federated-credential list --id "$APP_ID" --query "[?name=='$CREDENTIAL_NAME'].name" -o tsv 2>/dev/null || echo "")

    if [ -n "$EXISTING" ]; then
        print_warning "Credential '$CREDENTIAL_NAME' already exists, updating..."
        az ad app federated-credential delete --id "$APP_ID" --federated-credential-id "$CREDENTIAL_NAME" 2>/dev/null || true
    fi

    az ad app federated-credential create \
        --id "$APP_ID" \
        --parameters "{
            \"name\": \"$CREDENTIAL_NAME\",
            \"issuer\": \"https://token.actions.githubusercontent.com\",
            \"subject\": \"$SUBJECT\",
            \"description\": \"GitHub Actions for $GITHUB_REPO_FULL pull requests\",
            \"audiences\": [\"api://AzureADTokenExchange\"]
        }" >/dev/null

    print_success "Created federated credential for pull requests"
}

# =============================================================================
# Azure Role Assignments
# =============================================================================

assign_azure_roles() {
    print_header "Assigning Azure Roles"

    if [ "$DRY_RUN" = true ]; then
        print_status "[DRY RUN] Would assign Contributor role on subscription: $SUBSCRIPTION_ID"
        return
    fi

    # Assign Contributor role at subscription level
    print_status "Assigning Contributor role on subscription..."

    ROLE_ASSIGNMENT=$(az role assignment list \
        --assignee "$SP_OBJECT_ID" \
        --role "Contributor" \
        --scope "/subscriptions/$SUBSCRIPTION_ID" \
        --query "[0].id" -o tsv 2>/dev/null || echo "")

    if [ -n "$ROLE_ASSIGNMENT" ]; then
        print_warning "Contributor role already assigned"
    else
        az role assignment create \
            --assignee-object-id "$SP_OBJECT_ID" \
            --assignee-principal-type ServicePrincipal \
            --role "Contributor" \
            --scope "/subscriptions/$SUBSCRIPTION_ID" >/dev/null
        print_success "Assigned Contributor role"
    fi

    # Assign User Access Administrator role (for RBAC management)
    print_status "Assigning User Access Administrator role..."

    UAA_ASSIGNMENT=$(az role assignment list \
        --assignee "$SP_OBJECT_ID" \
        --role "User Access Administrator" \
        --scope "/subscriptions/$SUBSCRIPTION_ID" \
        --query "[0].id" -o tsv 2>/dev/null || echo "")

    if [ -n "$UAA_ASSIGNMENT" ]; then
        print_warning "User Access Administrator role already assigned"
    else
        az role assignment create \
            --assignee-object-id "$SP_OBJECT_ID" \
            --assignee-principal-type ServicePrincipal \
            --role "User Access Administrator" \
            --scope "/subscriptions/$SUBSCRIPTION_ID" >/dev/null
        print_success "Assigned User Access Administrator role"
    fi
}

# =============================================================================
# GitHub Configuration
# =============================================================================

configure_github() {
    print_header "Configuring GitHub Repository"

    if [ "$DRY_RUN" = true ]; then
        print_status "[DRY RUN] Would configure GitHub secrets and variables"
        return
    fi

    # Set repository-level secrets (for OIDC, we only need client ID, tenant ID, and subscription ID - no secrets!)
    print_status "Setting GitHub repository secrets for OIDC authentication..."

    # Remove old secret-based authentication if it exists
    print_status "Removing old secret-based authentication (if present)..."
    gh secret delete ARM_CLIENT_SECRET --repo "$GITHUB_REPO_FULL" 2>/dev/null || true
    gh secret delete AZURE_CREDENTIALS --repo "$GITHUB_REPO_FULL" 2>/dev/null || true

    # Set the OIDC configuration values
    echo "$APP_ID" | gh secret set AZURE_CLIENT_ID --repo "$GITHUB_REPO_FULL"
    echo "$TENANT_ID" | gh secret set AZURE_TENANT_ID --repo "$GITHUB_REPO_FULL"
    echo "$SUBSCRIPTION_ID" | gh secret set AZURE_SUBSCRIPTION_ID --repo "$GITHUB_REPO_FULL"

    print_success "GitHub OIDC secrets configured"

    # Create environments if they don't exist
    print_status "Creating GitHub environments..."

    for env in dev staging prod; do
        gh api \
            --method PUT \
            "/repos/$GITHUB_REPO_FULL/environments/$env" \
            --field "wait_timer=0" \
            2>/dev/null || print_warning "Environment '$env' may already exist"

        # Set environment-specific secrets
        echo "$APP_ID" | gh secret set AZURE_CLIENT_ID --env "$env" --repo "$GITHUB_REPO_FULL" 2>/dev/null || true
        echo "$TENANT_ID" | gh secret set AZURE_TENANT_ID --env "$env" --repo "$GITHUB_REPO_FULL" 2>/dev/null || true
        echo "$SUBSCRIPTION_ID" | gh secret set AZURE_SUBSCRIPTION_ID --env "$env" --repo "$GITHUB_REPO_FULL" 2>/dev/null || true
    done

    print_success "GitHub environments configured"
}

# =============================================================================
# Output Summary
# =============================================================================

print_summary() {
    print_header "OIDC Federation Setup Complete"

    echo -e "${GREEN}Configuration Summary:${NC}"
    echo "  Azure AD Application: $APP_NAME"
    echo "  Application (Client) ID: $APP_ID"
    echo "  Tenant ID: $TENANT_ID"
    echo "  Subscription ID: $SUBSCRIPTION_ID"
    echo "  GitHub Repository: $GITHUB_REPO_FULL"
    echo

    echo -e "${CYAN}Federated Credentials Created:${NC}"
    if [ "$DRY_RUN" != true ]; then
        az ad app federated-credential list --id "$APP_ID" --query "[].{Name:name, Subject:subject}" -o table
    fi
    echo

    echo -e "${YELLOW}GitHub Actions Workflow Update Required:${NC}"
    echo "Update your workflows to use OIDC authentication:"
    echo
    cat << 'EOF'
    jobs:
      deploy:
        runs-on: ubuntu-latest
        permissions:
          id-token: write    # Required for OIDC
          contents: read

        steps:
          - name: Azure Login (OIDC)
            uses: azure/login@v2
            with:
              client-id: ${{ secrets.AZURE_CLIENT_ID }}
              tenant-id: ${{ secrets.AZURE_TENANT_ID }}
              subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
EOF
    echo

    echo -e "${GREEN}Benefits of OIDC Authentication:${NC}"
    echo "  - No stored secrets (client secrets are not needed)"
    echo "  - Short-lived tokens (automatically expire after ~10 minutes)"
    echo "  - No manual rotation required"
    echo "  - Scoped to specific repos/branches/environments"
    echo "  - Azure issues tokens on-demand during workflow execution"
    echo

    echo -e "${CYAN}Documentation:${NC}"
    echo "  See docs/azure-github-oidc-setup.md for complete documentation"
    echo

    if [ "$DRY_RUN" = true ]; then
        print_warning "This was a dry run - no changes were made"
    fi
}

# =============================================================================
# Save Configuration
# =============================================================================

save_configuration() {
    if [ "$DRY_RUN" = true ]; then
        return
    fi

    print_header "Saving Configuration"

    # Save OIDC configuration to a file for reference
    local CONFIG_FILE="$PROJECT_ROOT/.azure-oidc-config.json"

    cat > "$CONFIG_FILE" << EOF
{
    "azure": {
        "appName": "$APP_NAME",
        "clientId": "$APP_ID",
        "tenantId": "$TENANT_ID",
        "subscriptionId": "$SUBSCRIPTION_ID",
        "servicePrincipalObjectId": "$SP_OBJECT_ID"
    },
    "github": {
        "organization": "$GITHUB_ORG",
        "repository": "$GITHUB_REPO"
    },
    "createdAt": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "authMethod": "oidc"
}
EOF

    print_success "Configuration saved to: $CONFIG_FILE"
    print_warning "This file contains sensitive information - do not commit to version control"

    # Ensure it's in .gitignore
    if ! grep -q ".azure-oidc-config.json" "$PROJECT_ROOT/.gitignore" 2>/dev/null; then
        echo ".azure-oidc-config.json" >> "$PROJECT_ROOT/.gitignore"
        print_status "Added .azure-oidc-config.json to .gitignore"
    fi
}

# =============================================================================
# Main Execution
# =============================================================================

main() {
    print_header "Azure to GitHub OIDC Federation Setup"
    echo "This script will configure workload identity federation between Azure and GitHub Actions."
    echo "This enables secure authentication without storing long-lived secrets."
    echo

    parse_arguments "$@"
    check_prerequisites
    detect_azure_config
    detect_github_config

    echo
    print_status "Ready to configure OIDC federation with the following settings:"
    echo "  Azure Subscription: $SUBSCRIPTION_NAME ($SUBSCRIPTION_ID)"
    echo "  Azure AD Application: $APP_NAME"
    echo "  GitHub Repository: $GITHUB_REPO_FULL"
    echo "  Environments: ${ENVIRONMENT:-all (dev, staging, prod)}"
    echo

    if [ "$DRY_RUN" = true ]; then
        print_warning "DRY RUN MODE - No changes will be made"
        echo
    else
        read -p "Do you want to proceed? (y/n): " CONFIRM
        if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
            print_status "Setup cancelled"
            exit 0
        fi
    fi

    create_azure_app
    create_federated_credentials
    assign_azure_roles
    configure_github
    save_configuration
    print_summary
}

main "$@"
