#!/bin/bash

# AKS Upgrade Pre-Flight Check Script
#
# This script performs comprehensive validation before AKS cluster upgrades,
# including version compatibility, cluster health, workload readiness, and
# resource capacity checks.
#
# Usage:
#   ./scripts/aks-upgrade-preflight.sh --environment dev --target-version 1.29.0
#   ./scripts/aks-upgrade-preflight.sh --environment prod --check-only

set -e

# ANSI color codes for consistent terminal output formatting
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
CHECK_ONLY=false
VERBOSE=false

# Counters for summary
CHECKS_PASSED=0
CHECKS_WARNED=0
CHECKS_FAILED=0

# Utility functions
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[PASS]${NC} $1"
    ((CHECKS_PASSED++))
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
    ((CHECKS_WARNED++))
}

print_error() {
    echo -e "${RED}[FAIL]${NC} $1"
    ((CHECKS_FAILED++))
}

print_header() {
    echo
    echo -e "${CYAN}=== $1 ===${NC}"
}

print_subheader() {
    echo -e "${BLUE}--- $1 ---${NC}"
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
            --project-name|-p)
                PROJECT_NAME="$2"
                shift 2
                ;;
            --check-only)
                CHECK_ONLY=true
                shift
                ;;
            --verbose)
                VERBOSE=true
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

    # Validate required arguments
    if [[ -z "$ENVIRONMENT" ]]; then
        print_error "Environment is required"
        show_help
        exit 1
    fi

    if [[ ! "$ENVIRONMENT" =~ ^(dev|staging|prod)$ ]]; then
        print_error "Environment must be one of: dev, staging, prod"
        exit 1
    fi

    if [[ "$CHECK_ONLY" != "true" && -z "$TARGET_VERSION" ]]; then
        print_error "Target version is required (use --check-only for health checks only)"
        show_help
        exit 1
    fi
}

show_help() {
    cat << EOF
AKS Upgrade Pre-Flight Check Script

Usage: $0 --environment ENV [OPTIONS]

Required Arguments:
  --environment, -e ENV     Target environment (dev|staging|prod)
  --target-version, -v VER  Target Kubernetes version (e.g., 1.29.0)

Options:
  --project-name, -p NAME   Project name (default: aks-platform)
  --check-only              Run health checks only, skip version compatibility
  --verbose                 Show detailed output
  --help, -h                Show this help message

Examples:
  $0 --environment dev --target-version 1.29.0
  $0 --environment prod --check-only
  $0 -e staging -v 1.29.0 --verbose
EOF
}

# Check prerequisites
check_prerequisites() {
    print_header "Checking Prerequisites"

    # Azure CLI
    if command -v az &>/dev/null; then
        local az_version=$(az --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
        print_success "Azure CLI installed (version: $az_version)"

        # Check authentication
        if az account show &>/dev/null; then
            local subscription=$(az account show --query name -o tsv)
            print_success "Authenticated to Azure (Subscription: $subscription)"
        else
            print_error "Not authenticated to Azure. Run 'az login'"
            return 1
        fi
    else
        print_error "Azure CLI not installed"
        return 1
    fi

    # kubectl
    if command -v kubectl &>/dev/null; then
        local kubectl_version=$(kubectl version --client -o json 2>/dev/null | jq -r '.clientVersion.gitVersion' | tr -d 'v')
        print_success "kubectl installed (version: $kubectl_version)"
    else
        print_error "kubectl not installed"
        return 1
    fi

    # jq
    if command -v jq &>/dev/null; then
        print_success "jq installed"
    else
        print_error "jq not installed (required for JSON parsing)"
        return 1
    fi
}

# Connect to cluster
connect_cluster() {
    print_header "Connecting to Cluster"

    local resource_group="rg-${PROJECT_NAME}-${ENVIRONMENT}"
    local cluster_name="aks-${PROJECT_NAME}-${ENVIRONMENT}"

    print_status "Connecting to cluster: $cluster_name"

    if az aks get-credentials --resource-group "$resource_group" --name "$cluster_name" --overwrite-existing &>/dev/null; then
        print_success "Connected to AKS cluster"
    else
        print_error "Failed to connect to AKS cluster"
        print_status "Verify cluster exists: az aks show -g $resource_group -n $cluster_name"
        return 1
    fi

    # Export variables for other functions
    export RESOURCE_GROUP="$resource_group"
    export CLUSTER_NAME="$cluster_name"
    export LOCATION=$(az aks show -g "$resource_group" -n "$cluster_name" --query location -o tsv)
}

# Check current version and upgrade path
check_version_compatibility() {
    print_header "Version Compatibility Check"

    # Get current version
    local current_version=$(az aks show -g "$RESOURCE_GROUP" -n "$CLUSTER_NAME" --query kubernetesVersion -o tsv)
    print_status "Current Kubernetes version: $current_version"

    if [[ "$CHECK_ONLY" == "true" ]]; then
        print_status "Skipping version compatibility (check-only mode)"
        return 0
    fi

    print_status "Target Kubernetes version: $TARGET_VERSION"

    # Get available upgrades
    print_subheader "Available Upgrade Paths"
    local upgrades=$(az aks get-upgrades -g "$RESOURCE_GROUP" -n "$CLUSTER_NAME" -o json)
    local available_versions=$(echo "$upgrades" | jq -r '.controlPlaneProfile.upgrades[]?.kubernetesVersion // empty' | sort -V)

    if [[ -z "$available_versions" ]]; then
        print_warning "No upgrades available from current version"
        echo "  Current version $current_version may be the latest supported"
        return 0
    fi

    echo "  Available versions:"
    echo "$available_versions" | while read -r v; do
        if [[ "$v" == "$TARGET_VERSION" ]]; then
            echo -e "    ${GREEN}* $v (target)${NC}"
        else
            echo "    - $v"
        fi
    done

    # Verify target version is available
    if echo "$available_versions" | grep -q "^${TARGET_VERSION}$"; then
        print_success "Target version $TARGET_VERSION is available for upgrade"
    else
        print_error "Target version $TARGET_VERSION is not available for upgrade"
        print_status "Available versions: $(echo "$available_versions" | tr '\n' ' ')"
        return 1
    fi

    # Check for minor version skip
    local current_minor=$(echo "$current_version" | cut -d. -f2)
    local target_minor=$(echo "$TARGET_VERSION" | cut -d. -f2)
    local version_diff=$((target_minor - current_minor))

    if [[ $version_diff -gt 1 ]]; then
        print_error "Cannot skip minor versions. Current: $current_version, Target: $TARGET_VERSION"
        return 1
    elif [[ $version_diff -eq 1 ]]; then
        print_success "Valid minor version upgrade"
    else
        print_success "Patch version upgrade"
    fi
}

# Check node pool health
check_node_pools() {
    print_header "Node Pool Health Check"

    # Get node pool info
    local node_pools=$(az aks nodepool list -g "$RESOURCE_GROUP" --cluster-name "$CLUSTER_NAME" -o json)
    local pool_count=$(echo "$node_pools" | jq length)

    print_status "Found $pool_count node pool(s)"

    echo "$node_pools" | jq -c '.[]' | while read -r pool; do
        local pool_name=$(echo "$pool" | jq -r '.name')
        local pool_version=$(echo "$pool" | jq -r '.currentOrchestratorVersion // .orchestratorVersion')
        local node_count=$(echo "$pool" | jq -r '.count')
        local min_count=$(echo "$pool" | jq -r '.minCount // "N/A"')
        local max_count=$(echo "$pool" | jq -r '.maxCount // "N/A"')
        local vm_size=$(echo "$pool" | jq -r '.vmSize')
        local provisioning_state=$(echo "$pool" | jq -r '.provisioningState')
        local power_state=$(echo "$pool" | jq -r '.powerState.code')
        local max_surge=$(echo "$pool" | jq -r '.upgradeSettings.maxSurge // "1"')

        print_subheader "Node Pool: $pool_name"
        echo "  Version: $pool_version"
        echo "  Nodes: $node_count (min: $min_count, max: $max_count)"
        echo "  VM Size: $vm_size"
        echo "  Max Surge: $max_surge"
        echo "  State: $provisioning_state / $power_state"

        if [[ "$provisioning_state" == "Succeeded" && "$power_state" == "Running" ]]; then
            print_success "Node pool $pool_name is healthy"
        else
            print_error "Node pool $pool_name is not healthy (State: $provisioning_state / $power_state)"
        fi
    done
}

# Check node health via kubectl
check_node_health() {
    print_header "Node Health Check"

    # Get node status
    local nodes=$(kubectl get nodes -o json)
    local total_nodes=$(echo "$nodes" | jq '.items | length')
    local ready_nodes=$(echo "$nodes" | jq '[.items[].status.conditions[] | select(.type=="Ready" and .status=="True")] | length')

    print_status "Total nodes: $total_nodes, Ready nodes: $ready_nodes"

    if [[ "$total_nodes" -eq "$ready_nodes" ]]; then
        print_success "All nodes are Ready"
    else
        print_error "$((total_nodes - ready_nodes)) node(s) are not Ready"
        kubectl get nodes | grep -v " Ready"
    fi

    # Check for node conditions
    print_subheader "Node Conditions"
    local problem_conditions=$(kubectl get nodes -o json | jq -r '.items[] | .metadata.name as $name | .status.conditions[] | select(.status=="True" and .type!="Ready") | "\($name): \(.type)"')

    if [[ -n "$problem_conditions" ]]; then
        print_warning "Nodes with active conditions:"
        echo "$problem_conditions" | while read -r condition; do
            echo "  $condition"
        done
    else
        print_success "No problematic node conditions found"
    fi

    # Check node resource pressure
    print_subheader "Node Resources"
    local pressure_nodes=$(kubectl get nodes -o json | jq -r '.items[] | select(.status.conditions[] | select((.type=="MemoryPressure" or .type=="DiskPressure" or .type=="PIDPressure") and .status=="True")) | .metadata.name')

    if [[ -n "$pressure_nodes" ]]; then
        print_warning "Nodes under resource pressure:"
        echo "$pressure_nodes" | while read -r node; do
            echo "  $node"
        done
    else
        print_success "No nodes under resource pressure"
    fi
}

# Check pod health
check_pod_health() {
    print_header "Pod Health Check"

    # Get pod status summary
    local pods=$(kubectl get pods --all-namespaces -o json)
    local total_pods=$(echo "$pods" | jq '.items | length')
    local running_pods=$(echo "$pods" | jq '[.items[] | select(.status.phase=="Running")] | length')
    local pending_pods=$(echo "$pods" | jq '[.items[] | select(.status.phase=="Pending")] | length')
    local failed_pods=$(echo "$pods" | jq '[.items[] | select(.status.phase=="Failed")] | length')

    print_status "Total pods: $total_pods"
    echo "  Running: $running_pods"
    echo "  Pending: $pending_pods"
    echo "  Failed: $failed_pods"

    # Check for problem pods
    print_subheader "Problem Pods"
    local problem_pods=$(kubectl get pods --all-namespaces --no-headers 2>/dev/null | grep -E "(Error|CrashLoopBackOff|ImagePullBackOff|Pending)" || true)

    if [[ -n "$problem_pods" ]]; then
        local problem_count=$(echo "$problem_pods" | wc -l | tr -d ' ')
        print_warning "$problem_count pod(s) with issues:"
        echo "$problem_pods" | head -20
        if [[ $problem_count -gt 20 ]]; then
            echo "  ... and $((problem_count - 20)) more"
        fi
    else
        print_success "No problem pods found"
    fi

    # Check for pods without resource limits
    print_subheader "Resource Configuration"
    local pods_without_limits=$(kubectl get pods --all-namespaces -o json | jq '[.items[] | select(.spec.containers[].resources.limits == null)] | length')

    if [[ "$pods_without_limits" -gt 0 ]]; then
        print_warning "$pods_without_limits pod(s) without resource limits"
    else
        print_success "All pods have resource limits configured"
    fi
}

# Check PodDisruptionBudgets
check_pdbs() {
    print_header "PodDisruptionBudget Check"

    local pdbs=$(kubectl get pdb --all-namespaces -o json)
    local pdb_count=$(echo "$pdbs" | jq '.items | length')

    print_status "Found $pdb_count PodDisruptionBudget(s)"

    if [[ $pdb_count -eq 0 ]]; then
        print_warning "No PodDisruptionBudgets found. Critical workloads may be disrupted during upgrade."
    else
        # Check for PDBs that might block upgrade
        echo "$pdbs" | jq -c '.items[]' | while read -r pdb; do
            local pdb_name=$(echo "$pdb" | jq -r '.metadata.name')
            local pdb_ns=$(echo "$pdb" | jq -r '.metadata.namespace')
            local min_available=$(echo "$pdb" | jq -r '.spec.minAvailable // "N/A"')
            local max_unavailable=$(echo "$pdb" | jq -r '.spec.maxUnavailable // "N/A"')
            local current_healthy=$(echo "$pdb" | jq -r '.status.currentHealthy')
            local desired_healthy=$(echo "$pdb" | jq -r '.status.desiredHealthy')
            local disruptions_allowed=$(echo "$pdb" | jq -r '.status.disruptionsAllowed')

            echo "  $pdb_ns/$pdb_name: minAvailable=$min_available, disruptionsAllowed=$disruptions_allowed"

            if [[ "$disruptions_allowed" == "0" ]]; then
                print_warning "PDB $pdb_ns/$pdb_name allows 0 disruptions - may block node drain"
            fi
        done

        print_success "PodDisruptionBudgets reviewed"
    fi
}

# Check for deprecated APIs
check_deprecated_apis() {
    print_header "Deprecated API Check"

    if [[ "$CHECK_ONLY" == "true" || -z "$TARGET_VERSION" ]]; then
        print_status "Skipping deprecated API check (no target version specified)"
        return 0
    fi

    print_status "Checking for deprecated Kubernetes APIs..."

    # Check if Pluto is installed
    if command -v pluto &>/dev/null; then
        print_status "Using Pluto for comprehensive API deprecation check"
        local pluto_output=$(pluto detect-all-in-cluster --target-versions "k8s=v$TARGET_VERSION" 2>/dev/null || true)

        if [[ -n "$pluto_output" && "$pluto_output" != *"No deprecated or removed APIs"* ]]; then
            print_warning "Deprecated APIs found:"
            echo "$pluto_output"
        else
            print_success "No deprecated APIs found for Kubernetes $TARGET_VERSION"
        fi
    else
        # Manual check for common deprecated APIs
        print_status "Pluto not installed. Performing basic API checks."

        # Check for extensions/v1beta1 Ingresses (removed in 1.22)
        local old_ingresses=$(kubectl get ingress --all-namespaces -o json 2>/dev/null | jq '[.items[] | select(.apiVersion | startswith("extensions/"))] | length')
        if [[ "$old_ingresses" -gt 0 ]]; then
            print_warning "$old_ingresses Ingress(es) using deprecated extensions/v1beta1 API"
        fi

        # Check for policy/v1beta1 PodSecurityPolicy (removed in 1.25)
        if kubectl api-resources | grep -q "podsecuritypolicies"; then
            local psp_count=$(kubectl get psp --no-headers 2>/dev/null | wc -l)
            if [[ $psp_count -gt 0 ]]; then
                print_warning "PodSecurityPolicies found - removed in Kubernetes 1.25+"
            fi
        fi

        print_success "Basic API deprecation check completed"
        print_status "Install Pluto for comprehensive checks: https://github.com/FairwindsOps/pluto"
    fi
}

# Check resource capacity for surge
check_capacity() {
    print_header "Capacity Check for Upgrade Surge"

    # Get node pool surge settings and calculate required capacity
    local node_pools=$(az aks nodepool list -g "$RESOURCE_GROUP" --cluster-name "$CLUSTER_NAME" -o json)

    echo "$node_pools" | jq -c '.[]' | while read -r pool; do
        local pool_name=$(echo "$pool" | jq -r '.name')
        local node_count=$(echo "$pool" | jq -r '.count')
        local max_count=$(echo "$pool" | jq -r '.maxCount // .count')
        local max_surge=$(echo "$pool" | jq -r '.upgradeSettings.maxSurge // "1"')
        local vm_size=$(echo "$pool" | jq -r '.vmSize')

        # Calculate surge nodes needed
        local surge_nodes=1
        if [[ "$max_surge" == *"%" ]]; then
            local percentage=${max_surge%\%}
            surge_nodes=$((node_count * percentage / 100))
            [[ $surge_nodes -lt 1 ]] && surge_nodes=1
        else
            surge_nodes=$max_surge
        fi

        local required_capacity=$((node_count + surge_nodes))

        print_subheader "Pool: $pool_name"
        echo "  Current nodes: $node_count"
        echo "  Max surge: $max_surge ($surge_nodes nodes)"
        echo "  Required capacity: $required_capacity"
        echo "  Max allowed: $max_count"

        if [[ $required_capacity -gt $max_count ]]; then
            print_warning "Pool $pool_name may need max_count increased ($required_capacity > $max_count)"
        else
            print_success "Pool $pool_name has sufficient capacity"
        fi
    done

    # Check Azure quota
    print_subheader "Azure VM Quota"
    local vm_family="standardDSv3Family"  # Common family, adjust as needed
    local quota_info=$(az vm list-usage --location "$LOCATION" -o json 2>/dev/null | jq ".[] | select(.name.value==\"$vm_family\")")

    if [[ -n "$quota_info" ]]; then
        local current_usage=$(echo "$quota_info" | jq -r '.currentValue')
        local limit=$(echo "$quota_info" | jq -r '.limit')
        local available=$((limit - current_usage))

        echo "  VM Family: $vm_family"
        echo "  Current usage: $current_usage / $limit"
        echo "  Available: $available"

        if [[ $available -lt 5 ]]; then
            print_warning "Low VM quota available. Consider requesting increase."
        else
            print_success "Sufficient VM quota available"
        fi
    else
        print_status "Could not retrieve quota information"
    fi
}

# Check critical services
check_critical_services() {
    print_header "Critical Services Check"

    # ArgoCD
    print_subheader "ArgoCD"
    if kubectl get namespace argocd &>/dev/null; then
        local argocd_pods=$(kubectl get pods -n argocd --no-headers 2>/dev/null | wc -l)
        local argocd_running=$(kubectl get pods -n argocd --no-headers 2>/dev/null | grep -c Running || echo "0")

        if [[ "$argocd_pods" -eq "$argocd_running" && "$argocd_pods" -gt 0 ]]; then
            print_success "ArgoCD is healthy ($argocd_running/$argocd_pods pods running)"
        else
            print_warning "ArgoCD has issues ($argocd_running/$argocd_pods pods running)"
        fi
    else
        print_status "ArgoCD namespace not found (may not be installed)"
    fi

    # Monitoring
    print_subheader "Monitoring Stack"
    if kubectl get namespace monitoring &>/dev/null; then
        local monitoring_pods=$(kubectl get pods -n monitoring --no-headers 2>/dev/null | wc -l)
        local monitoring_running=$(kubectl get pods -n monitoring --no-headers 2>/dev/null | grep -c Running || echo "0")

        if [[ "$monitoring_pods" -eq "$monitoring_running" && "$monitoring_pods" -gt 0 ]]; then
            print_success "Monitoring stack is healthy ($monitoring_running/$monitoring_pods pods running)"
        else
            print_warning "Monitoring stack has issues ($monitoring_running/$monitoring_pods pods running)"
        fi
    else
        print_status "Monitoring namespace not found (may not be installed)"
    fi

    # CoreDNS
    print_subheader "CoreDNS"
    local coredns_pods=$(kubectl get pods -n kube-system -l k8s-app=kube-dns --no-headers 2>/dev/null | wc -l)
    local coredns_running=$(kubectl get pods -n kube-system -l k8s-app=kube-dns --no-headers 2>/dev/null | grep -c Running || echo "0")

    if [[ "$coredns_pods" -eq "$coredns_running" && "$coredns_pods" -gt 0 ]]; then
        print_success "CoreDNS is healthy ($coredns_running/$coredns_pods pods running)"
    else
        print_error "CoreDNS has issues ($coredns_running/$coredns_pods pods running)"
    fi
}

# Generate report
generate_report() {
    print_header "Pre-Flight Check Summary"

    local total_checks=$((CHECKS_PASSED + CHECKS_WARNED + CHECKS_FAILED))

    echo
    echo "Environment: $ENVIRONMENT"
    echo "Cluster: $CLUSTER_NAME"
    if [[ -n "$TARGET_VERSION" ]]; then
        echo "Target Version: $TARGET_VERSION"
    fi
    echo
    echo -e "Results:"
    echo -e "  ${GREEN}Passed:${NC}  $CHECKS_PASSED"
    echo -e "  ${YELLOW}Warnings:${NC} $CHECKS_WARNED"
    echo -e "  ${RED}Failed:${NC}   $CHECKS_FAILED"
    echo -e "  Total:    $total_checks"
    echo

    if [[ $CHECKS_FAILED -gt 0 ]]; then
        echo -e "${RED}Pre-flight check FAILED${NC}"
        echo "Please resolve the failed checks before proceeding with the upgrade."
        return 1
    elif [[ $CHECKS_WARNED -gt 0 ]]; then
        echo -e "${YELLOW}Pre-flight check PASSED with warnings${NC}"
        echo "Review warnings before proceeding. Consider addressing them for a smoother upgrade."
        return 0
    else
        echo -e "${GREEN}Pre-flight check PASSED${NC}"
        echo "Cluster is ready for upgrade."
        return 0
    fi
}

# Main execution
main() {
    parse_arguments "$@"

    echo
    echo "AKS Upgrade Pre-Flight Check"
    echo "============================"
    echo "Environment: $ENVIRONMENT"
    if [[ -n "$TARGET_VERSION" ]]; then
        echo "Target Version: $TARGET_VERSION"
    fi
    if [[ "$CHECK_ONLY" == "true" ]]; then
        echo "Mode: Health Check Only"
    fi
    echo

    # Run checks
    check_prerequisites
    connect_cluster
    check_version_compatibility
    check_node_pools
    check_node_health
    check_pod_health
    check_pdbs
    check_deprecated_apis
    check_capacity
    check_critical_services

    # Generate summary
    generate_report
}

# Run main function
main "$@"
