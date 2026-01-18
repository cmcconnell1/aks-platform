#!/bin/bash

# AKS Upgrade Post-Validation Script
#
# This script performs comprehensive validation after AKS cluster upgrades,
# verifying cluster health, workload status, and service availability.
#
# Usage:
#   ./scripts/aks-upgrade-validate.sh --environment dev
#   ./scripts/aks-upgrade-validate.sh --environment prod --extended

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
PROJECT_NAME="${PROJECT_NAME:-aks-platform}"
EXTENDED=false
OUTPUT_FILE=""
VERBOSE=false

# Counters
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

# Parse arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --environment|-e)
                ENVIRONMENT="$2"
                shift 2
                ;;
            --project-name|-p)
                PROJECT_NAME="$2"
                shift 2
                ;;
            --extended)
                EXTENDED=true
                shift
                ;;
            --output|-o)
                OUTPUT_FILE="$2"
                shift 2
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

    if [[ -z "$ENVIRONMENT" ]]; then
        print_error "Environment is required"
        show_help
        exit 1
    fi

    if [[ ! "$ENVIRONMENT" =~ ^(dev|staging|prod)$ ]]; then
        print_error "Environment must be one of: dev, staging, prod"
        exit 1
    fi
}

show_help() {
    cat << EOF
AKS Upgrade Post-Validation Script

Usage: $0 --environment ENV [OPTIONS]

Required Arguments:
  --environment, -e ENV     Target environment (dev|staging|prod)

Options:
  --project-name, -p NAME   Project name (default: aks-platform)
  --extended                Run extended validation checks
  --output, -o FILE         Write results to file (JSON format)
  --verbose                 Show detailed output
  --help, -h                Show this help message

Examples:
  $0 --environment dev
  $0 --environment prod --extended
  $0 -e staging --output validation-results.json
EOF
}

# Connect to cluster
connect_cluster() {
    print_header "Connecting to Cluster"

    local resource_group="rg-${PROJECT_NAME}-${ENVIRONMENT}"
    local cluster_name="aks-${PROJECT_NAME}-${ENVIRONMENT}"

    if az aks get-credentials --resource-group "$resource_group" --name "$cluster_name" --overwrite-existing &>/dev/null; then
        print_success "Connected to AKS cluster: $cluster_name"
    else
        print_error "Failed to connect to AKS cluster"
        return 1
    fi

    export RESOURCE_GROUP="$resource_group"
    export CLUSTER_NAME="$cluster_name"
}

# Validate cluster version
validate_cluster_version() {
    print_header "Cluster Version Validation"

    # Get control plane version
    local control_plane_version=$(az aks show -g "$RESOURCE_GROUP" -n "$CLUSTER_NAME" --query kubernetesVersion -o tsv)
    print_status "Control plane version: $control_plane_version"

    # Get node pool versions
    local node_pools=$(az aks nodepool list -g "$RESOURCE_GROUP" --cluster-name "$CLUSTER_NAME" -o json)

    local version_mismatch=false
    echo "$node_pools" | jq -c '.[]' | while read -r pool; do
        local pool_name=$(echo "$pool" | jq -r '.name')
        local pool_version=$(echo "$pool" | jq -r '.currentOrchestratorVersion // .orchestratorVersion')

        echo "  Node pool '$pool_name': $pool_version"

        if [[ "$pool_version" != "$control_plane_version" ]]; then
            print_warning "Version mismatch: $pool_name ($pool_version) != control plane ($control_plane_version)"
            version_mismatch=true
        fi
    done

    if [[ "$version_mismatch" != "true" ]]; then
        print_success "All components running same Kubernetes version"
    fi
}

# Validate cluster health
validate_cluster_health() {
    print_header "Cluster Health Validation"

    # API server connectivity
    print_subheader "API Server"
    if kubectl cluster-info &>/dev/null; then
        print_success "API server is accessible"
    else
        print_error "API server is not accessible"
        return 1
    fi

    # Cluster provisioning state
    local provisioning_state=$(az aks show -g "$RESOURCE_GROUP" -n "$CLUSTER_NAME" --query provisioningState -o tsv)
    if [[ "$provisioning_state" == "Succeeded" ]]; then
        print_success "Cluster provisioning state: Succeeded"
    else
        print_error "Cluster provisioning state: $provisioning_state"
    fi

    # Power state
    local power_state=$(az aks show -g "$RESOURCE_GROUP" -n "$CLUSTER_NAME" --query powerState.code -o tsv)
    if [[ "$power_state" == "Running" ]]; then
        print_success "Cluster power state: Running"
    else
        print_error "Cluster power state: $power_state"
    fi
}

# Validate nodes
validate_nodes() {
    print_header "Node Validation"

    local nodes=$(kubectl get nodes -o json)
    local total_nodes=$(echo "$nodes" | jq '.items | length')
    local ready_nodes=$(echo "$nodes" | jq '[.items[] | select(.status.conditions[] | select(.type=="Ready" and .status=="True"))] | length')

    print_status "Total nodes: $total_nodes, Ready: $ready_nodes"

    if [[ "$total_nodes" -eq "$ready_nodes" ]]; then
        print_success "All nodes are Ready"
    else
        print_error "$((total_nodes - ready_nodes)) node(s) are not Ready"
        kubectl get nodes | grep -v " Ready" || true
    fi

    # Check node conditions
    print_subheader "Node Conditions"

    local problem_nodes=$(kubectl get nodes -o json | jq -r '
        .items[] |
        select(.status.conditions[] |
            select((.type=="MemoryPressure" or .type=="DiskPressure" or .type=="PIDPressure" or .type=="NetworkUnavailable") and .status=="True")
        ) |
        .metadata.name
    ')

    if [[ -n "$problem_nodes" ]]; then
        print_warning "Nodes with conditions:"
        echo "$problem_nodes" | while read -r node; do
            echo "  $node"
        done
    else
        print_success "No nodes with problematic conditions"
    fi

    # Check node versions match
    print_subheader "Node Versions"
    local unique_versions=$(kubectl get nodes -o jsonpath='{.items[*].status.nodeInfo.kubeletVersion}' | tr ' ' '\n' | sort -u | wc -l)

    if [[ $unique_versions -eq 1 ]]; then
        local version=$(kubectl get nodes -o jsonpath='{.items[0].status.nodeInfo.kubeletVersion}')
        print_success "All nodes running kubelet version: $version"
    else
        print_warning "Multiple kubelet versions detected"
        kubectl get nodes -o custom-columns=NAME:.metadata.name,VERSION:.status.nodeInfo.kubeletVersion
    fi
}

# Validate system pods
validate_system_pods() {
    print_header "System Pod Validation"

    local system_pods=$(kubectl get pods -n kube-system -o json)
    local total_pods=$(echo "$system_pods" | jq '.items | length')
    local running_pods=$(echo "$system_pods" | jq '[.items[] | select(.status.phase=="Running" or .status.phase=="Succeeded")] | length')

    print_status "System pods: $running_pods/$total_pods running/completed"

    # Check for problem pods
    local problem_pods=$(kubectl get pods -n kube-system --no-headers 2>/dev/null | grep -v -E "Running|Completed" || true)

    if [[ -n "$problem_pods" ]]; then
        print_warning "System pods with issues:"
        echo "$problem_pods"
    else
        print_success "All system pods are healthy"
    fi

    # Validate critical components
    print_subheader "Critical Components"

    # CoreDNS
    local coredns_ready=$(kubectl get deployment coredns -n kube-system -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    local coredns_desired=$(kubectl get deployment coredns -n kube-system -o jsonpath='{.status.replicas}' 2>/dev/null || echo "0")

    if [[ "$coredns_ready" -eq "$coredns_desired" && "$coredns_ready" -gt 0 ]]; then
        print_success "CoreDNS: $coredns_ready/$coredns_desired replicas ready"
    else
        print_error "CoreDNS: $coredns_ready/$coredns_desired replicas ready"
    fi

    # Metrics server
    if kubectl get deployment metrics-server -n kube-system &>/dev/null; then
        local metrics_ready=$(kubectl get deployment metrics-server -n kube-system -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
        if [[ "$metrics_ready" -gt 0 ]]; then
            print_success "Metrics server: Ready"
        else
            print_warning "Metrics server: Not ready"
        fi
    fi

    # Azure CNI / Network plugin
    local azure_cni_pods=$(kubectl get pods -n kube-system -l k8s-app=azure-cni-networkmonitor --no-headers 2>/dev/null | wc -l || echo "0")
    if [[ $azure_cni_pods -gt 0 ]]; then
        print_success "Azure CNI network monitor: $azure_cni_pods pod(s)"
    fi
}

# Validate workloads
validate_workloads() {
    print_header "Workload Validation"

    # Check all namespaces
    local namespaces=$(kubectl get namespaces -o jsonpath='{.items[*].metadata.name}')

    local total_deployments=0
    local ready_deployments=0
    local total_statefulsets=0
    local ready_statefulsets=0
    local total_daemonsets=0
    local ready_daemonsets=0

    for ns in $namespaces; do
        # Skip system namespaces for counting
        if [[ "$ns" =~ ^(kube-|default$) ]]; then
            continue
        fi

        # Deployments
        local deps=$(kubectl get deployments -n "$ns" -o json 2>/dev/null)
        local ns_deps=$(echo "$deps" | jq '.items | length')
        local ns_ready_deps=$(echo "$deps" | jq '[.items[] | select(.status.readyReplicas == .status.replicas)] | length')
        total_deployments=$((total_deployments + ns_deps))
        ready_deployments=$((ready_deployments + ns_ready_deps))

        # StatefulSets
        local sts=$(kubectl get statefulsets -n "$ns" -o json 2>/dev/null)
        local ns_sts=$(echo "$sts" | jq '.items | length')
        local ns_ready_sts=$(echo "$sts" | jq '[.items[] | select(.status.readyReplicas == .status.replicas)] | length')
        total_statefulsets=$((total_statefulsets + ns_sts))
        ready_statefulsets=$((ready_statefulsets + ns_ready_sts))

        # DaemonSets
        local ds=$(kubectl get daemonsets -n "$ns" -o json 2>/dev/null)
        local ns_ds=$(echo "$ds" | jq '.items | length')
        local ns_ready_ds=$(echo "$ds" | jq '[.items[] | select(.status.numberReady == .status.desiredNumberScheduled)] | length')
        total_daemonsets=$((total_daemonsets + ns_ds))
        ready_daemonsets=$((ready_daemonsets + ns_ready_ds))
    done

    print_subheader "Deployment Status"
    if [[ $total_deployments -gt 0 ]]; then
        if [[ $ready_deployments -eq $total_deployments ]]; then
            print_success "Deployments: $ready_deployments/$total_deployments ready"
        else
            print_warning "Deployments: $ready_deployments/$total_deployments ready"
        fi
    else
        print_status "No deployments found (outside system namespaces)"
    fi

    print_subheader "StatefulSet Status"
    if [[ $total_statefulsets -gt 0 ]]; then
        if [[ $ready_statefulsets -eq $total_statefulsets ]]; then
            print_success "StatefulSets: $ready_statefulsets/$total_statefulsets ready"
        else
            print_warning "StatefulSets: $ready_statefulsets/$total_statefulsets ready"
        fi
    else
        print_status "No statefulsets found"
    fi

    print_subheader "DaemonSet Status"
    if [[ $total_daemonsets -gt 0 ]]; then
        if [[ $ready_daemonsets -eq $total_daemonsets ]]; then
            print_success "DaemonSets: $ready_daemonsets/$total_daemonsets ready"
        else
            print_warning "DaemonSets: $ready_daemonsets/$total_daemonsets ready"
        fi
    else
        print_status "No daemonsets found"
    fi
}

# Validate platform services
validate_platform_services() {
    print_header "Platform Services Validation"

    # ArgoCD
    print_subheader "ArgoCD"
    if kubectl get namespace argocd &>/dev/null; then
        local argocd_pods=$(kubectl get pods -n argocd --no-headers 2>/dev/null | wc -l)
        local argocd_running=$(kubectl get pods -n argocd --no-headers 2>/dev/null | grep -c Running || echo "0")

        if [[ "$argocd_running" -eq "$argocd_pods" && "$argocd_pods" -gt 0 ]]; then
            print_success "ArgoCD: $argocd_running/$argocd_pods pods running"

            # Check ArgoCD server specifically
            if kubectl get deployment argocd-server -n argocd &>/dev/null; then
                local server_ready=$(kubectl get deployment argocd-server -n argocd -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
                if [[ "$server_ready" -gt 0 ]]; then
                    print_success "ArgoCD server is ready"
                else
                    print_warning "ArgoCD server not ready"
                fi
            fi
        else
            print_warning "ArgoCD: $argocd_running/$argocd_pods pods running"
        fi
    else
        print_status "ArgoCD not installed"
    fi

    # Monitoring
    print_subheader "Monitoring Stack"
    if kubectl get namespace monitoring &>/dev/null; then
        local monitoring_pods=$(kubectl get pods -n monitoring --no-headers 2>/dev/null | wc -l)
        local monitoring_running=$(kubectl get pods -n monitoring --no-headers 2>/dev/null | grep -c Running || echo "0")

        if [[ "$monitoring_running" -eq "$monitoring_pods" && "$monitoring_pods" -gt 0 ]]; then
            print_success "Monitoring: $monitoring_running/$monitoring_pods pods running"
        else
            print_warning "Monitoring: $monitoring_running/$monitoring_pods pods running"
        fi

        # Check Prometheus
        if kubectl get statefulset prometheus-kube-prometheus-stack-prometheus -n monitoring &>/dev/null 2>/dev/null; then
            local prom_ready=$(kubectl get statefulset prometheus-kube-prometheus-stack-prometheus -n monitoring -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
            if [[ "$prom_ready" -gt 0 ]]; then
                print_success "Prometheus is ready"
            else
                print_warning "Prometheus not ready"
            fi
        fi

        # Check Grafana
        if kubectl get deployment kube-prometheus-stack-grafana -n monitoring &>/dev/null 2>/dev/null; then
            local grafana_ready=$(kubectl get deployment kube-prometheus-stack-grafana -n monitoring -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
            if [[ "$grafana_ready" -gt 0 ]]; then
                print_success "Grafana is ready"
            else
                print_warning "Grafana not ready"
            fi
        fi
    else
        print_status "Monitoring stack not installed"
    fi

    # AI Tools
    print_subheader "AI Tools"
    if kubectl get namespace ai-tools &>/dev/null; then
        local ai_pods=$(kubectl get pods -n ai-tools --no-headers 2>/dev/null | wc -l)
        local ai_running=$(kubectl get pods -n ai-tools --no-headers 2>/dev/null | grep -c Running || echo "0")

        if [[ "$ai_pods" -gt 0 ]]; then
            if [[ "$ai_running" -eq "$ai_pods" ]]; then
                print_success "AI Tools: $ai_running/$ai_pods pods running"
            else
                print_warning "AI Tools: $ai_running/$ai_pods pods running"
            fi
        else
            print_status "No AI Tools pods found"
        fi
    else
        print_status "AI Tools namespace not found"
    fi
}

# Extended validation
validate_extended() {
    if [[ "$EXTENDED" != "true" ]]; then
        return 0
    fi

    print_header "Extended Validation"

    # DNS resolution test
    print_subheader "DNS Resolution"
    if kubectl run dns-test --image=busybox:1.36 --rm -i --restart=Never --command -- nslookup kubernetes.default.svc.cluster.local &>/dev/null; then
        print_success "DNS resolution working"
    else
        print_warning "DNS resolution test failed"
    fi

    # Service connectivity
    print_subheader "Internal Service Connectivity"
    if kubectl get svc kubernetes -n default &>/dev/null; then
        print_success "Kubernetes API service accessible"
    fi

    # PVC status
    print_subheader "Persistent Volume Claims"
    local pvc_count=$(kubectl get pvc --all-namespaces --no-headers 2>/dev/null | wc -l)
    local pvc_bound=$(kubectl get pvc --all-namespaces --no-headers 2>/dev/null | grep -c Bound || echo "0")

    if [[ $pvc_count -gt 0 ]]; then
        if [[ $pvc_bound -eq $pvc_count ]]; then
            print_success "PVCs: $pvc_bound/$pvc_count bound"
        else
            print_warning "PVCs: $pvc_bound/$pvc_count bound"
            kubectl get pvc --all-namespaces | grep -v Bound || true
        fi
    else
        print_status "No PVCs found"
    fi

    # Ingress status
    print_subheader "Ingress Resources"
    local ingress_count=$(kubectl get ingress --all-namespaces --no-headers 2>/dev/null | wc -l)
    if [[ $ingress_count -gt 0 ]]; then
        print_status "Found $ingress_count ingress resource(s)"
        kubectl get ingress --all-namespaces -o custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name,HOSTS:.spec.rules[*].host
    else
        print_status "No ingress resources found"
    fi

    # Certificate status
    print_subheader "Certificates"
    if kubectl get crd certificates.cert-manager.io &>/dev/null; then
        local cert_count=$(kubectl get certificates --all-namespaces --no-headers 2>/dev/null | wc -l)
        local cert_ready=$(kubectl get certificates --all-namespaces -o json 2>/dev/null | jq '[.items[] | select(.status.conditions[]? | select(.type=="Ready" and .status=="True"))] | length' || echo "0")

        if [[ $cert_count -gt 0 ]]; then
            if [[ $cert_ready -eq $cert_count ]]; then
                print_success "Certificates: $cert_ready/$cert_count ready"
            else
                print_warning "Certificates: $cert_ready/$cert_count ready"
            fi
        else
            print_status "No certificates found"
        fi
    else
        print_status "cert-manager not installed"
    fi

    # Resource metrics
    print_subheader "Resource Usage"
    if kubectl top nodes &>/dev/null; then
        print_status "Node resource usage:"
        kubectl top nodes
    else
        print_status "Metrics not available (metrics-server may need time to collect data)"
    fi
}

# Generate report
generate_report() {
    print_header "Validation Summary"

    local total_checks=$((CHECKS_PASSED + CHECKS_WARNED + CHECKS_FAILED))

    echo
    echo "Environment: $ENVIRONMENT"
    echo "Cluster: $CLUSTER_NAME"
    echo "Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo
    echo "Results:"
    echo -e "  ${GREEN}Passed:${NC}   $CHECKS_PASSED"
    echo -e "  ${YELLOW}Warnings:${NC} $CHECKS_WARNED"
    echo -e "  ${RED}Failed:${NC}   $CHECKS_FAILED"
    echo -e "  Total:    $total_checks"
    echo

    # Write JSON output if requested
    if [[ -n "$OUTPUT_FILE" ]]; then
        cat > "$OUTPUT_FILE" << EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "environment": "$ENVIRONMENT",
  "cluster": "$CLUSTER_NAME",
  "results": {
    "passed": $CHECKS_PASSED,
    "warnings": $CHECKS_WARNED,
    "failed": $CHECKS_FAILED,
    "total": $total_checks
  },
  "status": "$([ $CHECKS_FAILED -gt 0 ] && echo "FAILED" || ([ $CHECKS_WARNED -gt 0 ] && echo "WARNING" || echo "PASSED"))"
}
EOF
        print_status "Results written to: $OUTPUT_FILE"
    fi

    if [[ $CHECKS_FAILED -gt 0 ]]; then
        echo -e "${RED}Validation FAILED${NC}"
        echo "Please investigate the failed checks before considering the upgrade complete."
        return 1
    elif [[ $CHECKS_WARNED -gt 0 ]]; then
        echo -e "${YELLOW}Validation PASSED with warnings${NC}"
        echo "Review warnings to ensure they are acceptable."
        return 0
    else
        echo -e "${GREEN}Validation PASSED${NC}"
        echo "Cluster upgrade appears successful."
        return 0
    fi
}

# Main
main() {
    parse_arguments "$@"

    echo
    echo "AKS Upgrade Post-Validation"
    echo "==========================="
    echo "Environment: $ENVIRONMENT"
    if [[ "$EXTENDED" == "true" ]]; then
        echo "Mode: Extended validation"
    fi
    echo

    connect_cluster
    validate_cluster_version
    validate_cluster_health
    validate_nodes
    validate_system_pods
    validate_workloads
    validate_platform_services
    validate_extended

    generate_report
}

main "$@"
