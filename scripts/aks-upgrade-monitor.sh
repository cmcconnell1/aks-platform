#!/bin/bash

# AKS Upgrade Real-Time Monitor
#
# This script provides real-time monitoring of AKS cluster upgrades,
# showing node status, pod health, and upgrade progress.
#
# Usage:
#   ./scripts/aks-upgrade-monitor.sh --environment dev
#   ./scripts/aks-upgrade-monitor.sh --environment prod --interval 60

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

# Configuration
ENVIRONMENT=""
PROJECT_NAME="${PROJECT_NAME:-aks-platform}"
INTERVAL=30
MAX_DURATION=7200  # 2 hours default

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
            --interval|-i)
                INTERVAL="$2"
                shift 2
                ;;
            --max-duration)
                MAX_DURATION="$2"
                shift 2
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done

    if [[ -z "$ENVIRONMENT" ]]; then
        echo "Error: Environment is required"
        show_help
        exit 1
    fi
}

show_help() {
    cat << EOF
AKS Upgrade Real-Time Monitor

Usage: $0 --environment ENV [OPTIONS]

Required:
  --environment, -e ENV    Environment (dev|staging|prod)

Options:
  --project-name, -p NAME  Project name (default: aks-platform)
  --interval, -i SECS      Refresh interval in seconds (default: 30)
  --max-duration SECS      Max monitoring duration in seconds (default: 7200)
  --help, -h               Show this help

Press Ctrl+C to exit monitoring at any time.
EOF
}

connect_cluster() {
    local rg="rg-${PROJECT_NAME}-${ENVIRONMENT}"
    local cluster="aks-${PROJECT_NAME}-${ENVIRONMENT}"

    az aks get-credentials --resource-group "$rg" --name "$cluster" --overwrite-existing >/dev/null 2>&1

    export RESOURCE_GROUP="$rg"
    export CLUSTER_NAME="$cluster"
}

clear_screen() {
    printf "\033[H\033[J"
}

print_header() {
    echo -e "${CYAN}${BOLD}========================================${NC}"
    echo -e "${CYAN}${BOLD}  AKS Upgrade Monitor - $ENVIRONMENT${NC}"
    echo -e "${CYAN}${BOLD}========================================${NC}"
    echo -e "Cluster: ${BOLD}$CLUSTER_NAME${NC}"
    echo -e "Time: $(date '+%Y-%m-%d %H:%M:%S')"
    echo -e "Refresh: Every ${INTERVAL}s | Ctrl+C to exit"
    echo
}

show_cluster_status() {
    echo -e "${BLUE}${BOLD}Cluster Status${NC}"
    echo "----------------------------------------"

    local state=$(az aks show -g "$RESOURCE_GROUP" -n "$CLUSTER_NAME" --query provisioningState -o tsv 2>/dev/null)
    local version=$(az aks show -g "$RESOURCE_GROUP" -n "$CLUSTER_NAME" --query kubernetesVersion -o tsv 2>/dev/null)
    local power=$(az aks show -g "$RESOURCE_GROUP" -n "$CLUSTER_NAME" --query powerState.code -o tsv 2>/dev/null)

    local state_color=$GREEN
    [[ "$state" == "Updating" || "$state" == "Upgrading" ]] && state_color=$YELLOW
    [[ "$state" == "Failed" ]] && state_color=$RED

    echo -e "  Provisioning: ${state_color}${state}${NC}"
    echo -e "  K8s Version:  ${version}"
    echo -e "  Power State:  ${power}"
    echo
}

show_node_pools() {
    echo -e "${BLUE}${BOLD}Node Pools${NC}"
    echo "----------------------------------------"

    az aks nodepool list -g "$RESOURCE_GROUP" --cluster-name "$CLUSTER_NAME" -o json 2>/dev/null | \
    jq -r '.[] | "\(.name)|\(.provisioningState)|\(.currentOrchestratorVersion // .orchestratorVersion)|\(.count)|\(.minCount // "-")-\(.maxCount // "-")"' | \
    while IFS='|' read -r name state version count scale; do
        local state_color=$GREEN
        [[ "$state" == "Updating" || "$state" == "Upgrading" || "$state" == "Scaling" ]] && state_color=$YELLOW
        [[ "$state" == "Failed" ]] && state_color=$RED

        printf "  %-10s ${state_color}%-12s${NC} v%-8s Nodes: %-3s Scale: %s\n" "$name" "$state" "$version" "$count" "$scale"
    done
    echo
}

show_nodes() {
    echo -e "${BLUE}${BOLD}Node Status${NC}"
    echo "----------------------------------------"

    local nodes=$(kubectl get nodes -o json 2>/dev/null)
    local total=$(echo "$nodes" | jq '.items | length')
    local ready=$(echo "$nodes" | jq '[.items[] | select(.status.conditions[] | select(.type=="Ready" and .status=="True"))] | length')

    local status_color=$GREEN
    [[ $ready -lt $total ]] && status_color=$YELLOW

    echo -e "  Total: $total | Ready: ${status_color}${ready}${NC}"
    echo

    # Show each node
    echo "$nodes" | jq -r '.items[] | "\(.metadata.name)|\(.status.conditions[] | select(.type=="Ready") | .status)|\(.status.nodeInfo.kubeletVersion)|\(.metadata.labels["agentpool"] // "unknown")"' | \
    while IFS='|' read -r name ready version pool; do
        local status_icon="${GREEN}Ready${NC}"
        [[ "$ready" != "True" ]] && status_icon="${RED}NotReady${NC}"

        printf "    %-45s ${status_icon} %-12s %s\n" "$name" "$version" "($pool)"
    done
    echo
}

show_system_pods() {
    echo -e "${BLUE}${BOLD}System Pods${NC}"
    echo "----------------------------------------"

    local pods=$(kubectl get pods -n kube-system --no-headers 2>/dev/null)
    local total=$(echo "$pods" | wc -l | tr -d ' ')
    local running=$(echo "$pods" | grep -c Running || echo 0)
    local pending=$(echo "$pods" | grep -c Pending || echo 0)
    local failed=$(echo "$pods" | grep -c -E "Error|CrashLoop|ImagePull" || echo 0)

    echo -e "  Total: $total | Running: ${GREEN}$running${NC} | Pending: ${YELLOW}$pending${NC} | Failed: ${RED}$failed${NC}"

    if [[ $failed -gt 0 || $pending -gt 0 ]]; then
        echo
        echo "  Problem pods:"
        echo "$pods" | grep -v Running | head -5 | while read -r line; do
            echo "    $line"
        done
    fi
    echo
}

show_upgrade_progress() {
    echo -e "${BLUE}${BOLD}Upgrade Progress${NC}"
    echo "----------------------------------------"

    # Check for nodes being drained or cordoned
    local cordoned=$(kubectl get nodes --no-headers 2>/dev/null | grep -c SchedulingDisabled || echo 0)

    if [[ $cordoned -gt 0 ]]; then
        echo -e "  ${YELLOW}Nodes being upgraded: $cordoned${NC}"
    fi

    # Check for surge nodes (new nodes being added)
    local surge_nodes=$(kubectl get nodes -o json 2>/dev/null | jq '[.items[] | select(.metadata.creationTimestamp > (now - 600 | todate))] | length' 2>/dev/null || echo 0)

    if [[ $surge_nodes -gt 0 ]]; then
        echo -e "  ${CYAN}New nodes (surge): $surge_nodes${NC}"
    fi

    # Show pod disruption budgets status
    local pdb_blocked=$(kubectl get pdb --all-namespaces -o json 2>/dev/null | jq '[.items[] | select(.status.disruptionsAllowed == 0)] | length' 2>/dev/null || echo 0)

    if [[ $pdb_blocked -gt 0 ]]; then
        echo -e "  ${YELLOW}PDBs blocking disruption: $pdb_blocked${NC}"
    fi

    # Recent events
    echo
    echo "  Recent cluster events:"
    kubectl get events --all-namespaces --sort-by='.lastTimestamp' 2>/dev/null | \
    grep -E "NodeReady|NodeNotReady|Started|Drain|Cordon|Upgrade|Scale" | \
    tail -5 | while read -r line; do
        echo "    $line"
    done
    echo
}

monitor_loop() {
    local start_time=$(date +%s)

    while true; do
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))

        if [[ $elapsed -gt $MAX_DURATION ]]; then
            echo
            echo -e "${YELLOW}Max monitoring duration reached ($MAX_DURATION seconds)${NC}"
            break
        fi

        clear_screen
        print_header
        show_cluster_status
        show_node_pools
        show_nodes
        show_system_pods
        show_upgrade_progress

        echo -e "${CYAN}Monitoring for $((elapsed / 60))m $((elapsed % 60))s...${NC}"

        sleep "$INTERVAL"
    done
}

main() {
    parse_arguments "$@"

    echo "Connecting to cluster..."
    connect_cluster

    echo "Starting monitor (Ctrl+C to exit)..."
    sleep 2

    trap 'echo -e "\n${GREEN}Monitoring stopped.${NC}"; exit 0' INT

    monitor_loop
}

main "$@"
