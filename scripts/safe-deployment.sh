#!/bin/bash

# Safe Deployment Script for Azure AKS GitOps Platform
#
# This script implements safety mechanisms for deploying updates to production
# environments, including pre-deployment checks, health monitoring, and
# automatic rollback capabilities.
#
# Features:
# 1. Pre-deployment health baseline establishment
# 2. Progressive deployment with validation checkpoints
# 3. Real-time monitoring during deployment
# 4. Automatic rollback on failure detection
# 5. Post-deployment validation and reporting
#
# Usage:
#   ./scripts/safe-deployment.sh --environment prod --component infrastructure
#   ./scripts/safe-deployment.sh --environment staging --component platform-services
#   ./scripts/safe-deployment.sh --environment prod --component applications --dry-run

set -e  # Exit immediately if any command fails

# ANSI color codes for consistent terminal output formatting
RED='\033[0;31m'      # Error messages and failures
GREEN='\033[0;32m'    # Success messages and confirmations
YELLOW='\033[1;33m'   # Warning messages and important notes
BLUE='\033[0;34m'     # Informational messages and progress updates
NC='\033[0m'          # Reset to default terminal color

# Default configuration values
ENVIRONMENT=""
COMPONENT=""
DRY_RUN=false
BACKUP_ENABLED=true
MONITORING_ENABLED=true
ROLLBACK_ON_FAILURE=true
HEALTH_CHECK_TIMEOUT=300  # 5 minutes
DEPLOYMENT_TIMEOUT=1800   # 30 minutes

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
            --environment)
                ENVIRONMENT="$2"
                shift 2
                ;;
            --component)
                COMPONENT="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --no-backup)
                BACKUP_ENABLED=false
                shift
                ;;
            --no-rollback)
                ROLLBACK_ON_FAILURE=false
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

    # Validate required arguments
    if [[ -z "$ENVIRONMENT" || -z "$COMPONENT" ]]; then
        print_error "Environment and component are required"
        show_help
        exit 1
    fi

    # Validate environment
    if [[ ! "$ENVIRONMENT" =~ ^(dev|staging|prod)$ ]]; then
        print_error "Environment must be one of: dev, staging, prod"
        exit 1
    fi

    # Validate component
    if [[ ! "$COMPONENT" =~ ^(infrastructure|platform-services|applications|all)$ ]]; then
        print_error "Component must be one of: infrastructure, platform-services, applications, all"
        exit 1
    fi
}

# Display help information
show_help() {
    echo "Safe Deployment Script for Azure AKS GitOps Platform"
    echo
    echo "Usage: $0 --environment ENV --component COMP [OPTIONS]"
    echo
    echo "Required Arguments:"
    echo "  --environment ENV    Target environment (dev|staging|prod)"
    echo "  --component COMP     Component to deploy (infrastructure|platform-services|applications|all)"
    echo
    echo "Options:"
    echo "  --dry-run           Show what would be deployed without making changes"
    echo "  --no-backup         Skip pre-deployment backup creation"
    echo "  --no-rollback       Disable automatic rollback on failure"
    echo "  --help              Show this help message"
    echo
    echo "Examples:"
    echo "  $0 --environment prod --component infrastructure"
    echo "  $0 --environment staging --component platform-services --dry-run"
    echo "  $0 --environment prod --component all --no-backup"
}

# Establish health baseline before deployment
establish_health_baseline() {
    print_status "Establishing health baseline for $ENVIRONMENT environment..."
    
    local baseline_file="/tmp/health-baseline-${ENVIRONMENT}-$(date +%Y%m%d-%H%M%S).json"
    
    # Get AKS credentials
    print_status "Connecting to AKS cluster..."
    az aks get-credentials \
        --resource-group "rg-${PROJECT_NAME:-aks-platform}-${ENVIRONMENT}" \
        --name "aks-${PROJECT_NAME:-aks-platform}-${ENVIRONMENT}" \
        --overwrite-existing >/dev/null 2>&1 || {
        print_error "Failed to connect to AKS cluster"
        return 1
    }
    
    # Collect baseline metrics
    print_status "Collecting baseline metrics..."
    {
        echo "{"
        echo "  \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\","
        echo "  \"environment\": \"$ENVIRONMENT\","
        echo "  \"cluster_info\": {"
        
        # Node status
        echo "    \"nodes\": ["
        kubectl get nodes -o json | jq -c '.items[] | {name: .metadata.name, status: .status.conditions[-1].type, ready: (.status.conditions[-1].type == "Ready")}' | sed 's/$/,/' | sed '$s/,$//'
        echo "    ],"
        
        # Pod status by namespace
        echo "    \"pods\": ["
        kubectl get pods --all-namespaces -o json | jq -c '.items[] | {namespace: .metadata.namespace, name: .metadata.name, phase: .status.phase, ready: (.status.conditions[]? | select(.type=="Ready") | .status)}' | sed 's/$/,/' | sed '$s/,$//'
        echo "    ],"
        
        # Service status
        echo "    \"services\": ["
        kubectl get services --all-namespaces -o json | jq -c '.items[] | {namespace: .metadata.namespace, name: .metadata.name, type: .spec.type}' | sed 's/$/,/' | sed '$s/,$//'
        echo "    ]"
        
        echo "  }"
        echo "}"
    } > "$baseline_file"
    
    # Store baseline file path for later comparison
    echo "$baseline_file" > "/tmp/baseline-file-${ENVIRONMENT}"
    
    print_success "Health baseline established: $baseline_file"
    
    # Quick health check
    local unhealthy_nodes=$(kubectl get nodes --no-headers | grep -v Ready | wc -l)
    local failed_pods=$(kubectl get pods --all-namespaces --no-headers | grep -E "(Error|CrashLoopBackOff|ImagePullBackOff)" | wc -l)
    
    if [[ $unhealthy_nodes -gt 0 ]]; then
        print_warning "$unhealthy_nodes unhealthy nodes detected"
    fi
    
    if [[ $failed_pods -gt 0 ]]; then
        print_warning "$failed_pods failed pods detected"
    fi
    
    if [[ $unhealthy_nodes -gt 0 || $failed_pods -gt 0 ]]; then
        print_warning "Environment has pre-existing issues. Proceed with caution."
        read -p "Continue with deployment? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_status "Deployment cancelled by user"
            exit 0
        fi
    fi
}

# Create pre-deployment backup
create_backup() {
    if [[ "$BACKUP_ENABLED" != "true" ]]; then
        print_status "Backup creation disabled, skipping..."
        return 0
    fi
    
    print_status "Creating pre-deployment backup..."
    
    local backup_dir="/tmp/backup-${ENVIRONMENT}-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$backup_dir"
    
    # Backup Terraform state
    if [[ "$COMPONENT" == "infrastructure" || "$COMPONENT" == "all" ]]; then
        print_status "Backing up Terraform state..."
        cd terraform
        terraform state pull > "$backup_dir/terraform.tfstate"
        cd ..
    fi
    
    # Backup Kubernetes resources
    if [[ "$COMPONENT" == "platform-services" || "$COMPONENT" == "applications" || "$COMPONENT" == "all" ]]; then
        print_status "Backing up Kubernetes resources..."
        
        # Backup critical namespaces
        for namespace in argocd monitoring ai-tools; do
            if kubectl get namespace "$namespace" >/dev/null 2>&1; then
                kubectl get all,configmaps,secrets,pvc -n "$namespace" -o yaml > "$backup_dir/${namespace}-resources.yaml"
            fi
        done
        
        # Backup ArgoCD applications
        if kubectl get namespace argocd >/dev/null 2>&1; then
            kubectl get applications -n argocd -o yaml > "$backup_dir/argocd-applications.yaml"
        fi
    fi
    
    # Store backup directory path
    echo "$backup_dir" > "/tmp/backup-dir-${ENVIRONMENT}"
    
    print_success "Backup created: $backup_dir"
}

# Deploy infrastructure components
deploy_infrastructure() {
    print_status "Deploying infrastructure components..."
    
    cd terraform
    
    # Initialize Terraform
    print_status "Initializing Terraform..."
    terraform init -backend-config="environments/${ENVIRONMENT}/backend.conf"
    
    # Generate plan
    print_status "Generating Terraform plan..."
    terraform plan \
        -var-file="environments/${ENVIRONMENT}/terraform.tfvars" \
        -out="${ENVIRONMENT}.tfplan"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_status "Dry run mode - skipping actual deployment"
        cd ..
        return 0
    fi
    
    # Apply changes
    print_status "Applying Terraform changes..."
    terraform apply -auto-approve "${ENVIRONMENT}.tfplan"
    
    cd ..
    print_success "Infrastructure deployment completed"
}

# Deploy platform services
deploy_platform_services() {
    print_status "Deploying platform services..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_status "Dry run mode - would deploy platform services"
        return 0
    fi
    
    # Update ArgoCD if it exists
    if kubectl get namespace argocd >/dev/null 2>&1; then
        print_status "Syncing ArgoCD applications..."
        
        # Sync platform applications
        for app in monitoring-stack ai-tools-stack; do
            if kubectl get application "$app" -n argocd >/dev/null 2>&1; then
                print_status "Syncing application: $app"
                kubectl patch application "$app" -n argocd -p '{"operation":{"sync":{}}}' --type merge
                
                # Wait for sync to complete
                local timeout=300
                local elapsed=0
                while [[ $elapsed -lt $timeout ]]; do
                    local status=$(kubectl get application "$app" -n argocd -o jsonpath='{.status.sync.status}')
                    if [[ "$status" == "Synced" ]]; then
                        print_success "Application $app synced successfully"
                        break
                    fi
                    sleep 10
                    elapsed=$((elapsed + 10))
                done
                
                if [[ $elapsed -ge $timeout ]]; then
                    print_error "Timeout waiting for application $app to sync"
                    return 1
                fi
            fi
        done
    fi
    
    print_success "Platform services deployment completed"
}

# Deploy applications
deploy_applications() {
    print_status "Deploying applications..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_status "Dry run mode - would deploy applications"
        return 0
    fi
    
    # Apply application manifests if they exist
    if [[ -d "applications" ]]; then
        print_status "Applying application manifests..."
        kubectl apply -f applications/ --recursive
    fi
    
    print_success "Applications deployment completed"
}

# Monitor deployment health
monitor_deployment_health() {
    print_status "Monitoring deployment health..."
    
    local start_time=$(date +%s)
    local timeout=$DEPLOYMENT_TIMEOUT
    
    while true; do
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        
        if [[ $elapsed -gt $timeout ]]; then
            print_error "Deployment monitoring timeout reached"
            return 1
        fi
        
        # Check for failed pods
        local failed_pods=$(kubectl get pods --all-namespaces --no-headers | grep -E "(Error|CrashLoopBackOff|ImagePullBackOff)" | wc -l)
        
        if [[ $failed_pods -gt 0 ]]; then
            print_warning "Detected $failed_pods failed pods"
            kubectl get pods --all-namespaces | grep -E "(Error|CrashLoopBackOff|ImagePullBackOff)"
            
            if [[ "$ROLLBACK_ON_FAILURE" == "true" ]]; then
                print_error "Triggering automatic rollback due to failed pods"
                return 1
            fi
        fi
        
        # Check node health
        local unhealthy_nodes=$(kubectl get nodes --no-headers | grep -v Ready | wc -l)
        
        if [[ $unhealthy_nodes -gt 0 ]]; then
            print_warning "Detected $unhealthy_nodes unhealthy nodes"
            
            if [[ "$ROLLBACK_ON_FAILURE" == "true" ]]; then
                print_error "Triggering automatic rollback due to unhealthy nodes"
                return 1
            fi
        fi
        
        # If we've made it this far without issues, deployment is healthy
        if [[ $elapsed -gt 60 ]]; then  # Wait at least 1 minute before declaring success
            print_success "Deployment appears healthy after $elapsed seconds"
            break
        fi
        
        sleep 30
    done
}

# Perform post-deployment validation
validate_deployment() {
    print_status "Performing post-deployment validation..."
    
    # Basic cluster health
    print_status "Checking cluster health..."
    kubectl cluster-info >/dev/null 2>&1 || {
        print_error "Cluster info check failed"
        return 1
    }
    
    # Check critical services
    print_status "Checking critical services..."
    
    # ArgoCD health
    if kubectl get namespace argocd >/dev/null 2>&1; then
        local argocd_pods=$(kubectl get pods -n argocd --no-headers | grep -v Running | wc -l)
        if [[ $argocd_pods -gt 0 ]]; then
            print_warning "ArgoCD has $argocd_pods non-running pods"
        else
            print_success "ArgoCD is healthy"
        fi
    fi
    
    # Monitoring health
    if kubectl get namespace monitoring >/dev/null 2>&1; then
        local monitoring_pods=$(kubectl get pods -n monitoring --no-headers | grep -v Running | wc -l)
        if [[ $monitoring_pods -gt 0 ]]; then
            print_warning "Monitoring has $monitoring_pods non-running pods"
        else
            print_success "Monitoring stack is healthy"
        fi
    fi
    
    print_success "Post-deployment validation completed"
}

# Execute rollback procedure
execute_rollback() {
    print_error "Executing rollback procedure..."
    
    local backup_dir
    if [[ -f "/tmp/backup-dir-${ENVIRONMENT}" ]]; then
        backup_dir=$(cat "/tmp/backup-dir-${ENVIRONMENT}")
    else
        print_error "No backup directory found for rollback"
        return 1
    fi
    
    if [[ ! -d "$backup_dir" ]]; then
        print_error "Backup directory not found: $backup_dir"
        return 1
    fi
    
    # Rollback infrastructure if needed
    if [[ "$COMPONENT" == "infrastructure" || "$COMPONENT" == "all" ]]; then
        if [[ -f "$backup_dir/terraform.tfstate" ]]; then
            print_status "Rolling back Terraform state..."
            cd terraform
            terraform state push "$backup_dir/terraform.tfstate"
            cd ..
        fi
    fi
    
    # Rollback Kubernetes resources if needed
    if [[ "$COMPONENT" == "platform-services" || "$COMPONENT" == "applications" || "$COMPONENT" == "all" ]]; then
        print_status "Rolling back Kubernetes resources..."
        
        # Restore ArgoCD applications
        if [[ -f "$backup_dir/argocd-applications.yaml" ]]; then
            kubectl apply -f "$backup_dir/argocd-applications.yaml"
        fi
        
        # Restore namespace resources
        for namespace_file in "$backup_dir"/*-resources.yaml; do
            if [[ -f "$namespace_file" ]]; then
                kubectl apply -f "$namespace_file"
            fi
        done
    fi
    
    print_success "Rollback procedure completed"
}

# Main execution function
main() {
    parse_arguments "$@"
    
    print_status "Starting safe deployment for $ENVIRONMENT environment, component: $COMPONENT"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_status "DRY RUN MODE - No actual changes will be made"
    fi
    
    # Establish health baseline
    establish_health_baseline || {
        print_error "Failed to establish health baseline"
        exit 1
    }
    
    # Create backup
    create_backup || {
        print_error "Failed to create backup"
        exit 1
    }
    
    # Deploy components based on selection
    deployment_failed=false
    
    case "$COMPONENT" in
        infrastructure)
            deploy_infrastructure || deployment_failed=true
            ;;
        platform-services)
            deploy_platform_services || deployment_failed=true
            ;;
        applications)
            deploy_applications || deployment_failed=true
            ;;
        all)
            deploy_infrastructure || deployment_failed=true
            if [[ "$deployment_failed" != "true" ]]; then
                deploy_platform_services || deployment_failed=true
            fi
            if [[ "$deployment_failed" != "true" ]]; then
                deploy_applications || deployment_failed=true
            fi
            ;;
    esac
    
    # Monitor deployment health (skip for dry run)
    if [[ "$DRY_RUN" != "true" && "$deployment_failed" != "true" ]]; then
        monitor_deployment_health || deployment_failed=true
    fi
    
    # Handle deployment failure
    if [[ "$deployment_failed" == "true" ]]; then
        if [[ "$ROLLBACK_ON_FAILURE" == "true" && "$DRY_RUN" != "true" ]]; then
            execute_rollback
        fi
        print_error "Deployment failed"
        exit 1
    fi
    
    # Validate deployment (skip for dry run)
    if [[ "$DRY_RUN" != "true" ]]; then
        validate_deployment || {
            print_error "Post-deployment validation failed"
            if [[ "$ROLLBACK_ON_FAILURE" == "true" ]]; then
                execute_rollback
            fi
            exit 1
        }
    fi
    
    print_success "Safe deployment completed successfully!"
    
    if [[ "$DRY_RUN" != "true" ]]; then
        print_status "Continue monitoring the environment for the next 24-48 hours"
        print_status "Backup location: $(cat "/tmp/backup-dir-${ENVIRONMENT}" 2>/dev/null || echo "Not available")"
    fi
}

# Run main function with all arguments
main "$@"
