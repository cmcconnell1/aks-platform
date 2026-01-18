#!/bin/bash

# AKS Cluster Upgrade Execution Script
#
# This script executes AKS cluster upgrades using either Terraform or Azure CLI,
# with built-in safety mechanisms, progress monitoring, and automatic state management.
#
# Usage:
#   ./scripts/aks-upgrade-execute.sh --environment dev --target-version 1.29.0 --method terraform
#   ./scripts/aks-upgrade-execute.sh --environment prod --target-version 1.29.0 --method cli
#   ./scripts/aks-upgrade-execute.sh --environment staging --node-image-only

set -e

# ANSI color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Default configuration
ENVIRONMENT=""
TARGET_VERSION=""
PROJECT_NAME="${PROJECT_NAME:-aks-platform}"
METHOD="terraform"  # terraform or cli
DRY_RUN=false
NODE_IMAGE_ONLY=false
CONTROL_PLANE_ONLY=false
SKIP_PREFLIGHT=false
SKIP_VALIDATION=false
NODE_POOL=""
BACKUP_STATE=true

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Utility functions
print_status() {
    echo -e "${BLUE}[INFO]${NC} $(date '+%H:%M:%S') $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $(date '+%H:%M:%S') $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $(date '+%H:%M:%S') $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%H:%M:%S') $1"
}

print_header() {
    echo
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${CYAN}========================================${NC}"
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --environment|-e)
                ENVIRONMENT="$2"
                shift 2
                ;;
            --target-version|-v)
                TARGET_VERSION="$2"
                shift 2
                ;;
            --method|-m)
                METHOD="$2"
                shift 2
                ;;
            --project-name|-p)
                PROJECT_NAME="$2"
                shift 2
                ;;
            --node-pool)
                NODE_POOL="$2"
                shift 2
                ;;
            --node-image-only)
                NODE_IMAGE_ONLY=true
                shift
                ;;
            --control-plane-only)
                CONTROL_PLANE_ONLY=true
                shift
                ;;
            --skip-preflight)
                SKIP_PREFLIGHT=true
                shift
                ;;
            --skip-validation)
                SKIP_VALIDATION=true
                shift
                ;;
            --no-backup)
                BACKUP_STATE=false
                shift
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

    # Validate arguments
    if [[ -z "$ENVIRONMENT" ]]; then
        print_error "Environment is required"
        show_help
        exit 1
    fi

    if [[ ! "$ENVIRONMENT" =~ ^(dev|staging|prod)$ ]]; then
        print_error "Environment must be one of: dev, staging, prod"
        exit 1
    fi

    if [[ "$NODE_IMAGE_ONLY" != "true" && -z "$TARGET_VERSION" ]]; then
        print_error "Target version is required (unless using --node-image-only)"
        show_help
        exit 1
    fi

    if [[ ! "$METHOD" =~ ^(terraform|cli)$ ]]; then
        print_error "Method must be one of: terraform, cli"
        exit 1
    fi
}

show_help() {
    cat << EOF
AKS Cluster Upgrade Execution Script

Usage: $0 --environment ENV --target-version VER [OPTIONS]

Required Arguments:
  --environment, -e ENV       Target environment (dev|staging|prod)
  --target-version, -v VER    Target Kubernetes version (e.g., 1.29.0)

Options:
  --method, -m METHOD         Upgrade method: terraform (default) or cli
  --project-name, -p NAME     Project name (default: aks-platform)
  --node-pool POOL            Upgrade specific node pool only
  --node-image-only           Update node images without version change
  --control-plane-only        Upgrade control plane only (CLI method)
  --skip-preflight            Skip pre-flight checks
  --skip-validation           Skip post-upgrade validation
  --no-backup                 Skip Terraform state backup
  --dry-run                   Show what would be done without making changes
  --help, -h                  Show this help message

Examples:
  # Full upgrade using Terraform (recommended)
  $0 --environment dev --target-version 1.29.0 --method terraform

  # Upgrade using Azure CLI
  $0 --environment staging --target-version 1.29.0 --method cli

  # Upgrade control plane only
  $0 --environment prod --target-version 1.29.0 --method cli --control-plane-only

  # Node image update only
  $0 --environment prod --node-image-only

  # Upgrade specific node pool
  $0 --environment dev --target-version 1.29.0 --method cli --node-pool user

  # Dry run to see what would happen
  $0 --environment prod --target-version 1.29.0 --dry-run
EOF
}

# Set cluster variables
set_cluster_vars() {
    export RESOURCE_GROUP="rg-${PROJECT_NAME}-${ENVIRONMENT}"
    export CLUSTER_NAME="aks-${PROJECT_NAME}-${ENVIRONMENT}"
    export LOCATION=$(az aks show -g "$RESOURCE_GROUP" -n "$CLUSTER_NAME" --query location -o tsv 2>/dev/null || echo "eastus")
}

# Run pre-flight checks
run_preflight() {
    if [[ "$SKIP_PREFLIGHT" == "true" ]]; then
        print_warning "Skipping pre-flight checks (--skip-preflight)"
        return 0
    fi

    print_header "Running Pre-Flight Checks"

    local preflight_args="--environment $ENVIRONMENT"
    if [[ -n "$TARGET_VERSION" ]]; then
        preflight_args="$preflight_args --target-version $TARGET_VERSION"
    else
        preflight_args="$preflight_args --check-only"
    fi

    if ! "$SCRIPT_DIR/aks-upgrade-preflight.sh" $preflight_args; then
        print_error "Pre-flight checks failed. Resolve issues before proceeding."
        print_status "Use --skip-preflight to bypass (not recommended)"
        return 1
    fi

    print_success "Pre-flight checks passed"
}

# Backup Terraform state
backup_terraform_state() {
    if [[ "$BACKUP_STATE" != "true" ]]; then
        print_status "Skipping Terraform state backup (--no-backup)"
        return 0
    fi

    print_status "Backing up Terraform state..."

    local backup_dir="$PROJECT_ROOT/.upgrade-backups"
    local backup_file="$backup_dir/terraform-${ENVIRONMENT}-$(date +%Y%m%d-%H%M%S).tfstate"

    mkdir -p "$backup_dir"

    cd "$PROJECT_ROOT/terraform"

    # Initialize if needed
    if [[ ! -d ".terraform" ]]; then
        terraform init -backend-config="environments/${ENVIRONMENT}/backend.conf" -input=false >/dev/null
    fi

    # Pull current state
    terraform state pull > "$backup_file"

    if [[ -s "$backup_file" ]]; then
        print_success "State backed up to: $backup_file"
        export BACKUP_FILE="$backup_file"
    else
        print_warning "State backup may be empty (new deployment?)"
    fi

    cd "$PROJECT_ROOT"
}

# Update Terraform variables for upgrade
update_terraform_vars() {
    print_status "Preparing Terraform configuration for upgrade..."

    local tfvars_file="$PROJECT_ROOT/terraform/environments/${ENVIRONMENT}/terraform.tfvars"

    if [[ ! -f "$tfvars_file" ]]; then
        print_error "Terraform variables file not found: $tfvars_file"
        return 1
    fi

    # Check current version in tfvars
    local current_tfvars_version=$(grep -E "^kubernetes_version" "$tfvars_file" | grep -oE "[0-9]+\.[0-9]+\.[0-9]+" || echo "not set")
    print_status "Current version in tfvars: $current_tfvars_version"
    print_status "Target version: $TARGET_VERSION"

    if [[ "$DRY_RUN" == "true" ]]; then
        print_status "[DRY RUN] Would update kubernetes_version to $TARGET_VERSION"
        return 0
    fi

    # Update the version in tfvars
    if grep -q "^kubernetes_version" "$tfvars_file"; then
        # Update existing line
        sed -i.bak "s/^kubernetes_version.*=.*/kubernetes_version = \"$TARGET_VERSION\"/" "$tfvars_file"
    else
        # Add new line
        echo "kubernetes_version = \"$TARGET_VERSION\"" >> "$tfvars_file"
    fi

    print_success "Updated kubernetes_version to $TARGET_VERSION in $tfvars_file"
}

# Execute Terraform upgrade
execute_terraform_upgrade() {
    print_header "Executing Terraform Upgrade"

    cd "$PROJECT_ROOT/terraform"

    # Initialize Terraform
    print_status "Initializing Terraform..."
    terraform init -backend-config="environments/${ENVIRONMENT}/backend.conf" -input=false

    # Update tfvars with new version
    update_terraform_vars

    # Generate plan
    print_status "Generating Terraform plan..."
    local plan_file="${ENVIRONMENT}-upgrade.tfplan"

    if [[ -f "environments/${ENVIRONMENT}/terraform.tfvars" ]]; then
        terraform plan \
            -var-file="environments/${ENVIRONMENT}/terraform.tfvars" \
            -out="$plan_file"
    else
        terraform plan \
            -var="environment=${ENVIRONMENT}" \
            -var="kubernetes_version=${TARGET_VERSION}" \
            -out="$plan_file"
    fi

    # Show plan summary
    print_status "Plan summary:"
    terraform show -no-color "$plan_file" | grep -E "^(Plan:|  # |will be|must be)" | head -20

    if [[ "$DRY_RUN" == "true" ]]; then
        print_status "[DRY RUN] Would apply the above plan"
        cd "$PROJECT_ROOT"
        return 0
    fi

    # Confirm before applying
    echo
    print_warning "This will upgrade the AKS cluster. This operation cannot be easily reversed."
    read -p "Proceed with upgrade? (yes/no): " confirm
    if [[ "$confirm" != "yes" ]]; then
        print_status "Upgrade cancelled by user"
        cd "$PROJECT_ROOT"
        exit 0
    fi

    # Apply the plan
    print_status "Applying Terraform changes..."
    local start_time=$(date +%s)

    if terraform apply -auto-approve "$plan_file"; then
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        print_success "Terraform apply completed in $((duration / 60))m $((duration % 60))s"
    else
        print_error "Terraform apply failed"
        print_status "State backup available at: ${BACKUP_FILE:-N/A}"
        cd "$PROJECT_ROOT"
        return 1
    fi

    cd "$PROJECT_ROOT"
}

# Execute Azure CLI upgrade
execute_cli_upgrade() {
    print_header "Executing Azure CLI Upgrade"

    local start_time=$(date +%s)

    if [[ "$NODE_IMAGE_ONLY" == "true" ]]; then
        # Node image update
        print_status "Updating node images..."

        local pools
        if [[ -n "$NODE_POOL" ]]; then
            pools=("$NODE_POOL")
        else
            pools=($(az aks nodepool list -g "$RESOURCE_GROUP" --cluster-name "$CLUSTER_NAME" --query "[].name" -o tsv))
        fi

        for pool in "${pools[@]}"; do
            print_status "Updating node images for pool: $pool"

            if [[ "$DRY_RUN" == "true" ]]; then
                print_status "[DRY RUN] Would update node image for pool: $pool"
                continue
            fi

            az aks nodepool upgrade \
                --resource-group "$RESOURCE_GROUP" \
                --cluster-name "$CLUSTER_NAME" \
                --name "$pool" \
                --node-image-only \
                --no-wait

            print_status "Node image update initiated for pool: $pool"
        done

    elif [[ "$CONTROL_PLANE_ONLY" == "true" ]]; then
        # Control plane only upgrade
        print_status "Upgrading control plane to $TARGET_VERSION..."

        if [[ "$DRY_RUN" == "true" ]]; then
            print_status "[DRY RUN] Would upgrade control plane to $TARGET_VERSION"
            return 0
        fi

        az aks upgrade \
            --resource-group "$RESOURCE_GROUP" \
            --name "$CLUSTER_NAME" \
            --kubernetes-version "$TARGET_VERSION" \
            --control-plane-only \
            --yes

    elif [[ -n "$NODE_POOL" ]]; then
        # Specific node pool upgrade
        print_status "Upgrading node pool $NODE_POOL to $TARGET_VERSION..."

        if [[ "$DRY_RUN" == "true" ]]; then
            print_status "[DRY RUN] Would upgrade node pool $NODE_POOL to $TARGET_VERSION"
            return 0
        fi

        az aks nodepool upgrade \
            --resource-group "$RESOURCE_GROUP" \
            --cluster-name "$CLUSTER_NAME" \
            --name "$NODE_POOL" \
            --kubernetes-version "$TARGET_VERSION"

    else
        # Full cluster upgrade
        print_status "Upgrading entire cluster to $TARGET_VERSION..."

        if [[ "$DRY_RUN" == "true" ]]; then
            print_status "[DRY RUN] Would upgrade cluster to $TARGET_VERSION"
            return 0
        fi

        # Confirm before proceeding
        echo
        print_warning "This will upgrade the entire AKS cluster (control plane + all node pools)."
        print_warning "This operation cannot be easily reversed."
        read -p "Proceed with upgrade? (yes/no): " confirm
        if [[ "$confirm" != "yes" ]]; then
            print_status "Upgrade cancelled by user"
            exit 0
        fi

        az aks upgrade \
            --resource-group "$RESOURCE_GROUP" \
            --name "$CLUSTER_NAME" \
            --kubernetes-version "$TARGET_VERSION" \
            --yes
    fi

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    print_success "CLI upgrade completed in $((duration / 60))m $((duration % 60))s"
}

# Monitor upgrade progress
monitor_upgrade() {
    print_header "Monitoring Upgrade Progress"

    print_status "Refreshing cluster credentials..."
    az aks get-credentials --resource-group "$RESOURCE_GROUP" --name "$CLUSTER_NAME" --overwrite-existing >/dev/null

    print_status "Watching node upgrade progress (Ctrl+C to exit monitoring)..."
    echo

    local timeout=1800  # 30 minutes
    local elapsed=0
    local interval=30

    while [[ $elapsed -lt $timeout ]]; do
        echo -e "\n${BLUE}--- Status at $(date '+%H:%M:%S') ---${NC}"

        # Node status
        echo "Nodes:"
        kubectl get nodes -o wide 2>/dev/null | grep -E "NAME|Ready|NotReady" || echo "  Unable to fetch nodes"

        # Check for upgrading nodes
        local upgrading_nodes=$(kubectl get nodes -o json 2>/dev/null | jq -r '.items[] | select(.metadata.labels["node.kubernetes.io/exclude-from-external-load-balancers"]=="true") | .metadata.name' | wc -l)

        if [[ $upgrading_nodes -gt 0 ]]; then
            echo "  Nodes being upgraded: $upgrading_nodes"
        fi

        # Check provisioning state
        local cluster_state=$(az aks show -g "$RESOURCE_GROUP" -n "$CLUSTER_NAME" --query provisioningState -o tsv 2>/dev/null)
        echo "Cluster provisioning state: $cluster_state"

        if [[ "$cluster_state" == "Succeeded" ]]; then
            local current_version=$(az aks show -g "$RESOURCE_GROUP" -n "$CLUSTER_NAME" --query kubernetesVersion -o tsv)
            echo "Current Kubernetes version: $current_version"

            if [[ "$current_version" == "$TARGET_VERSION" ]] || [[ "$NODE_IMAGE_ONLY" == "true" ]]; then
                print_success "Upgrade appears complete!"
                break
            fi
        elif [[ "$cluster_state" == "Failed" ]]; then
            print_error "Cluster entered Failed state!"
            return 1
        fi

        sleep $interval
        elapsed=$((elapsed + interval))
    done

    if [[ $elapsed -ge $timeout ]]; then
        print_warning "Monitoring timeout reached. Check Azure portal for status."
    fi
}

# Run post-upgrade validation
run_validation() {
    if [[ "$SKIP_VALIDATION" == "true" ]]; then
        print_warning "Skipping post-upgrade validation (--skip-validation)"
        return 0
    fi

    print_header "Running Post-Upgrade Validation"

    if [[ -f "$SCRIPT_DIR/aks-upgrade-validate.sh" ]]; then
        if ! "$SCRIPT_DIR/aks-upgrade-validate.sh" --environment "$ENVIRONMENT"; then
            print_warning "Post-upgrade validation reported issues. Review the output above."
            return 1
        fi
    else
        print_status "Validation script not found, running basic checks..."

        # Basic validation
        print_status "Verifying cluster access..."
        kubectl cluster-info >/dev/null

        print_status "Checking node status..."
        kubectl get nodes

        print_status "Checking system pods..."
        kubectl get pods -n kube-system | grep -v Running | grep -v Completed || print_success "All system pods healthy"
    fi

    print_success "Post-upgrade validation completed"
}

# Sync Terraform state after CLI upgrade
sync_terraform_state() {
    if [[ "$METHOD" != "cli" ]]; then
        return 0
    fi

    print_header "Syncing Terraform State"

    print_status "After CLI upgrades, Terraform state may be out of sync."
    print_status "Recommended: Update terraform.tfvars and run 'terraform apply'"

    local tfvars_file="$PROJECT_ROOT/terraform/environments/${ENVIRONMENT}/terraform.tfvars"

    if [[ -f "$tfvars_file" ]]; then
        local current_version=$(az aks show -g "$RESOURCE_GROUP" -n "$CLUSTER_NAME" --query kubernetesVersion -o tsv)
        print_status "Current cluster version: $current_version"
        print_status "Update $tfvars_file with: kubernetes_version = \"$current_version\""
    fi
}

# Print summary
print_summary() {
    print_header "Upgrade Summary"

    echo "Environment: $ENVIRONMENT"
    echo "Cluster: $CLUSTER_NAME"
    echo "Method: $METHOD"

    if [[ "$NODE_IMAGE_ONLY" == "true" ]]; then
        echo "Type: Node Image Update"
    elif [[ "$CONTROL_PLANE_ONLY" == "true" ]]; then
        echo "Type: Control Plane Only"
        echo "Target Version: $TARGET_VERSION"
    else
        echo "Type: Full Cluster Upgrade"
        echo "Target Version: $TARGET_VERSION"
    fi

    if [[ -n "$BACKUP_FILE" ]]; then
        echo "State Backup: $BACKUP_FILE"
    fi

    echo
    print_status "Next steps:"
    echo "  1. Monitor cluster health for 24-48 hours"
    echo "  2. Verify application functionality"
    echo "  3. Update documentation with upgrade details"

    if [[ "$METHOD" == "cli" ]]; then
        echo "  4. Sync Terraform state with actual cluster version"
    fi
}

# Main execution
main() {
    parse_arguments "$@"

    echo
    echo "AKS Cluster Upgrade"
    echo "==================="
    echo "Environment: $ENVIRONMENT"
    if [[ -n "$TARGET_VERSION" ]]; then
        echo "Target Version: $TARGET_VERSION"
    fi
    echo "Method: $METHOD"
    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${YELLOW}Mode: DRY RUN${NC}"
    fi
    echo

    # Set cluster variables
    set_cluster_vars

    # Run pre-flight checks
    run_preflight

    # Backup state (Terraform method)
    if [[ "$METHOD" == "terraform" ]]; then
        backup_terraform_state
    fi

    # Execute upgrade
    if [[ "$METHOD" == "terraform" ]]; then
        execute_terraform_upgrade
    else
        execute_cli_upgrade
    fi

    # Monitor progress (skip for dry run)
    if [[ "$DRY_RUN" != "true" ]]; then
        monitor_upgrade
    fi

    # Run validation (skip for dry run)
    if [[ "$DRY_RUN" != "true" ]]; then
        run_validation
    fi

    # Sync state after CLI upgrade
    sync_terraform_state

    # Print summary
    print_summary

    print_success "Upgrade process completed!"
}

# Run main function
main "$@"
