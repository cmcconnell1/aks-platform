#!/bin/bash

# Unified Azure Cost Monitor
#
# This script provides comprehensive Azure cost monitoring including cost estimation,
# actual billing analysis, budget alerts, and automated scheduling. It consolidates
# all cost-related functionality into a single, easy-to-use interface.
#
# Features:
# 1. Cost estimation using Azure pricing data
# 2. Actual billing cost monitoring via Azure Cost Management API
# 3. Budget alerts and threshold monitoring
# 4. Automated scheduling with cron jobs
# 5. Webhook notifications (Slack, Teams, etc.)
# 6. Dashboard generation and serving
# 7. Historical cost tracking and trend analysis
# 8. Integration with monitoring systems
#
# Usage:
#   ./scripts/cost-monitor.sh                    # Current month actual costs
#   ./scripts/cost-monitor.sh --estimate         # Cost estimation only
#   ./scripts/cost-monitor.sh --days 7          # Last 7 days actual costs
#   ./scripts/cost-monitor.sh --env prod        # Production environment only
#   ./scripts/cost-monitor.sh --budget 1000     # With budget alerts
#   ./scripts/cost-monitor.sh --schedule daily  # Set up daily monitoring
#   ./scripts/cost-monitor.sh --dashboard       # Generate HTML dashboard

set -e

# Source virtual environment utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/venv-utils.sh"

# ANSI color codes for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Default configuration
PROJECT_NAME="aks-platform"
DAYS=""
ENVIRONMENT=""
BUDGET=""
SCHEDULE=""
EXPORT_FILE=""
QUIET=false
INSTALL_DEPS=false
NOTIFICATION_WEBHOOK=""
MODE="actual"  # actual, estimate, dashboard
REGION="eastus"
SERVE_DASHBOARD=false
DASHBOARD_PORT=8080

# Utility functions
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

# Show help information
show_help() {
    echo "Unified Azure Cost Monitor"
    echo
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Modes:"
    echo "  --actual              Show actual Azure billing costs (default)"
    echo "  --estimate            Show cost estimates using Azure pricing"
    echo "  --dashboard           Generate HTML cost dashboard"
    echo
    echo "Options:"
    echo "  --project-name NAME    Project name (default: aks-platform)"
    echo "  --env ENVIRONMENT      Environment: dev, staging, prod"
    echo "  --days NUMBER          Number of days to analyze (default: current month)"
    echo "  --budget AMOUNT        Budget limit for alerts (USD)"
    echo "  --region REGION        Azure region for estimates (default: eastus)"
    echo "  --schedule FREQUENCY   Set up scheduled monitoring (daily, weekly, monthly)"
    echo "  --export FILE          Export results to JSON file"
    echo "  --serve               Serve dashboard via HTTP (with --dashboard)"
    echo "  --port PORT           Dashboard port (default: 8080)"
    echo "  --quiet               Minimal output for scripting"
    echo "  --install-deps        Install required Python dependencies"
    echo "  --webhook URL         Webhook URL for notifications"
    echo "  --help                Show this help message"
    echo
    echo "Examples:"
    echo "  $0                                    # Current month actual costs"
    echo "  $0 --estimate --env dev --region westus2 # Cost estimates for dev environment"
    echo "  $0 --actual --days 7 --env prod     # Last 7 days actual costs, production"
    echo "  $0 --dashboard --serve --port 8080   # Live cost dashboard"
    echo "  $0 --budget 1000 --webhook URL      # With budget alerts and notifications"
    echo "  $0 --schedule daily --budget 500    # Set up daily monitoring with alerts"
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --actual)
                MODE="actual"
                shift
                ;;
            --estimate)
                MODE="estimate"
                shift
                ;;
            --dashboard)
                MODE="dashboard"
                shift
                ;;
            --project-name)
                PROJECT_NAME="$2"
                shift 2
                ;;
            --env|--environment)
                ENVIRONMENT="$2"
                shift 2
                ;;
            --days)
                DAYS="$2"
                shift 2
                ;;
            --budget)
                BUDGET="$2"
                shift 2
                ;;
            --region)
                REGION="$2"
                shift 2
                ;;
            --schedule)
                SCHEDULE="$2"
                shift 2
                ;;
            --export)
                EXPORT_FILE="$2"
                shift 2
                ;;
            --serve)
                SERVE_DASHBOARD=true
                shift
                ;;
            --port)
                DASHBOARD_PORT="$2"
                shift 2
                ;;
            --quiet)
                QUIET=true
                shift
                ;;
            --install-deps)
                INSTALL_DEPS=true
                shift
                ;;
            --webhook)
                NOTIFICATION_WEBHOOK="$2"
                shift 2
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
}

# Check and install dependencies with virtual environment support
check_dependencies() {
    # Check virtual environment status
    check_virtual_environment

    if [[ "$INSTALL_DEPS" == "true" ]]; then
        print_status "Installing Python dependencies..."
        local packages=("azure-mgmt-costmanagement" "azure-identity" "azure-mgmt-resource" "requests")
        install_python_packages_with_venv "${packages[@]}"
        return 0
    fi

    # Check if Python script exists
    if [[ ! -f "scripts/azure-cost-monitor.py" ]]; then
        print_error "azure-cost-monitor.py not found in scripts directory"
        exit 1
    fi

    # Check if Azure CLI is available
    if ! command -v az >/dev/null 2>&1; then
        print_error "Azure CLI is not installed"
        print_status "Install with: curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash"
        exit 1
    fi

    # Check if logged in to Azure
    if ! az account show >/dev/null 2>&1; then
        print_error "Not logged in to Azure. Please run 'az login' first"
        exit 1
    fi

    # Check Python dependencies
    local missing_packages
    missing_packages=$(check_python_packages "azure.mgmt.costmanagement" "azure.identity" "azure.mgmt.resource" "requests")

    if [[ -n "$missing_packages" ]]; then
        print_warning "Python dependencies not found: $missing_packages"
        print_status "Install with virtual environment:"
        print_status "  ./scripts/setup-python-env.sh"
        print_status "  source venv/bin/activate"
        print_status "  pip install azure-mgmt-costmanagement azure-identity azure-mgmt-resource requests"
        print_status "Or run with --install-deps to install automatically"
        exit 1
    fi
}

# Set up scheduled monitoring
setup_schedule() {
    local frequency="$1"
    local cron_schedule=""
    
    case "$frequency" in
        daily)
            cron_schedule="0 9 * * *"  # 9 AM daily
            ;;
        weekly)
            cron_schedule="0 9 * * 1"  # 9 AM every Monday
            ;;
        monthly)
            cron_schedule="0 9 1 * *"  # 9 AM on 1st of each month
            ;;
        *)
            print_error "Invalid schedule frequency: $frequency"
            print_status "Valid options: daily, weekly, monthly"
            exit 1
            ;;
    esac
    
    # Create cron job
    local script_path="$(realpath "$0")"
    local cron_command="$script_path --project-name $PROJECT_NAME"
    
    if [[ -n "$ENVIRONMENT" ]]; then
        cron_command="$cron_command --env $ENVIRONMENT"
    fi
    
    if [[ -n "$BUDGET" ]]; then
        cron_command="$cron_command --budget $BUDGET"
    fi
    
    if [[ -n "$NOTIFICATION_WEBHOOK" ]]; then
        cron_command="$cron_command --webhook $NOTIFICATION_WEBHOOK"
    fi
    
    cron_command="$cron_command --quiet"
    
    # Add to crontab
    (crontab -l 2>/dev/null; echo "$cron_schedule $cron_command") | crontab -
    
    print_success "Scheduled $frequency cost monitoring"
    print_status "Cron job: $cron_schedule $cron_command"
}

# Cost estimation function (replaces estimate-costs.sh and dynamic-cost-estimator.py)
estimate_costs() {
    local environment="${1:-dev}"
    local region="${2:-eastus}"

    if [[ "$QUIET" != "true" ]]; then
        print_status "Estimating costs for $environment environment in $region region"
        echo
    fi

    # Base costs per environment (monthly estimates in USD)
    local base_cost_dev="220"
    local base_cost_staging="380"
    local base_cost_prod="1000"

    local ai_cost_dev="430"
    local ai_cost_staging="840"
    local ai_cost_prod="2600"

    # Get base cost for environment
    local base_cost
    local ai_cost
    case "$environment" in
        dev)
            base_cost="$base_cost_dev"
            ai_cost="$ai_cost_dev"
            ;;
        staging)
            base_cost="$base_cost_staging"
            ai_cost="$ai_cost_staging"
            ;;
        prod)
            base_cost="$base_cost_prod"
            ai_cost="$ai_cost_prod"
            ;;
        *)
            base_cost="$base_cost_dev"
            ai_cost="$ai_cost_dev"
            ;;
    esac

    # Regional multipliers (US regions only)
    local multiplier="1.0"
    case "$region" in
        eastus) multiplier="1.0" ;;
        westus) multiplier="1.05" ;;
        westus2) multiplier="1.02" ;;
        centralus) multiplier="1.0" ;;
        eastus2) multiplier="1.0" ;;
        southcentralus) multiplier="1.03" ;;
        northcentralus) multiplier="1.02" ;;
        westcentralus) multiplier="1.04" ;;
        *) multiplier="1.0" ;;  # Default to East US pricing
    esac



    # Calculate costs
    local base_total=$(echo "scale=2; $base_cost * $multiplier" | bc -l 2>/dev/null || echo "$base_cost")
    local ai_total=$(echo "scale=2; $ai_cost * $multiplier" | bc -l 2>/dev/null || echo "$ai_cost")

    # All costs are in USD - no currency conversion needed
    # This ensures consistent pricing across all documentation and examples

    if [[ "$QUIET" == "true" ]]; then
        echo "$base_total"
        return 0
    fi

    # Generate detailed estimate report
    cat << EOF
Cost Estimation Report
======================
Project: $PROJECT_NAME
Environment: $environment
Region: $region
Currency: USD

Base Infrastructure Cost: $base_total USD/month
With AI/ML Tools: $ai_total USD/month

Cost Breakdown:
- AKS Cluster (2-3 nodes): $(echo "scale=2; $base_total * 0.4" | bc -l) USD
- Application Gateway: $(echo "scale=2; $base_total * 0.25" | bc -l) USD
- Storage & Networking: $(echo "scale=2; $base_total * 0.2" | bc -l) USD
- Monitoring & Logs: $(echo "scale=2; $base_total * 0.15" | bc -l) USD

Optional AI/ML Add-ons:
- GPU Node Pool: $(echo "scale=2; ($ai_total - $base_total) * 0.7" | bc -l) USD
- Enhanced Storage: $(echo "scale=2; ($ai_total - $base_total) * 0.3" | bc -l) USD

Regional Multiplier: ${multiplier}x

Note: These are estimates based on typical usage patterns.
Actual costs may vary based on usage, data transfer, and Azure pricing changes.
Use --actual mode to see real billing costs.
EOF

    # Export if requested
    if [[ -n "$EXPORT_FILE" ]]; then
        cat > "$EXPORT_FILE" << EOF
{
  "project_name": "$PROJECT_NAME",
  "environment": "$environment",
  "region": "$region",
  "currency": "USD",
  "base_cost": $base_total,
  "ai_cost": $ai_total,
  "regional_multiplier": $multiplier,
  "generated_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
        print_success "Estimate exported to: $EXPORT_FILE"
    fi
}

# Send notification
send_notification() {
    local message="$1"
    local status="$2"
    
    if [[ -z "$NOTIFICATION_WEBHOOK" ]]; then
        return 0
    fi
    
    # Determine color based on status
    local color="good"
    case "$status" in
        critical) color="danger" ;;
        warning) color="warning" ;;
        *) color="good" ;;
    esac
    
    # Send Slack notification (assuming Slack webhook format)
    local payload=$(cat <<EOF
{
    "attachments": [
        {
            "color": "$color",
            "title": "Azure Cost Alert - $PROJECT_NAME",
            "text": "$message",
            "footer": "Azure Cost Monitor",
            "ts": $(date +%s)
        }
    ]
}
EOF
)
    
    curl -X POST -H 'Content-type: application/json' \
         --data "$payload" \
         "$NOTIFICATION_WEBHOOK" >/dev/null 2>&1 || {
        print_warning "Failed to send notification"
    }
}

# Generate cost summary for notifications
generate_cost_summary() {
    local cost_data="$1"
    local budget="$2"
    
    # Parse JSON data (simplified - in practice would use jq)
    local total_cost=$(echo "$cost_data" | grep -o '"total_cost": [0-9.]*' | cut -d' ' -f2)
    local period=$(echo "$cost_data" | grep -o '"period": "[^"]*"' | cut -d'"' -f4)
    
    local summary="Cost Summary for $PROJECT_NAME"
    summary="$summary\nPeriod: $period"
    summary="$summary\nTotal Cost: \$$total_cost"
    
    if [[ -n "$budget" ]]; then
        local percentage=$(echo "scale=1; $total_cost * 100 / $budget" | bc -l 2>/dev/null || echo "0")
        summary="$summary\nBudget: \$$budget (${percentage}% used)"
    fi
    
    echo -e "$summary"
}

# Main execution function
main() {
    parse_arguments "$@"

    if [[ "$QUIET" != "true" ]]; then
        print_status "Unified Azure Cost Monitor - $PROJECT_NAME"
        print_status "Mode: $MODE"
        echo
    fi

    # Check dependencies based on mode
    case "$MODE" in
        actual)
            check_dependencies
            ;;
        estimate)
            # No dependencies needed for estimation mode
            ;;
        dashboard)
            # Check if dashboard script exists
            if [[ ! -f "scripts/cost-dashboard.sh" ]]; then
                print_error "cost-dashboard.sh not found"
                exit 1
            fi
            ;;
    esac

    # Set up scheduling if requested
    if [[ -n "$SCHEDULE" ]]; then
        setup_schedule "$SCHEDULE"
        exit 0
    fi

    # Execute based on mode
    case "$MODE" in
        estimate)
            estimate_costs "$ENVIRONMENT" "$REGION"
            ;;
        dashboard)
            generate_dashboard
            ;;
        actual)
            run_actual_cost_monitoring
            ;;
        *)
            print_error "Unknown mode: $MODE"
            exit 1
            ;;
    esac
}

# Generate dashboard
generate_dashboard() {
    if [[ "$SERVE_DASHBOARD" == "true" ]]; then
        ./scripts/cost-dashboard.sh --project-name "$PROJECT_NAME" --serve --port "$DASHBOARD_PORT" ${BUDGET:+--budget "$BUDGET"}
    else
        local output_file="${EXPORT_FILE:-cost-dashboard.html}"
        ./scripts/cost-dashboard.sh --project-name "$PROJECT_NAME" --output "$output_file" ${BUDGET:+--budget "$BUDGET"}
        if [[ "$QUIET" != "true" ]]; then
            print_success "Dashboard generated: $output_file"
        fi
    fi
}

# Run actual cost monitoring using Python script
run_actual_cost_monitoring() {
    # Check if Python script exists
    if [[ ! -f "scripts/azure-cost-monitor.py" ]]; then
        print_error "azure-cost-monitor.py not found"
        exit 1
    fi

    # Build Python script arguments
    local python_args="--project-name $PROJECT_NAME"

    if [[ -n "$ENVIRONMENT" ]]; then
        python_args="$python_args --environment $ENVIRONMENT"
    fi

    if [[ -n "$DAYS" ]]; then
        python_args="$python_args --days $DAYS"
    else
        python_args="$python_args --current-month"
    fi

    if [[ -n "$BUDGET" ]]; then
        python_args="$python_args --budget-alert $BUDGET"
    fi

    if [[ -n "$EXPORT_FILE" ]]; then
        python_args="$python_args --export $EXPORT_FILE"
    fi

    if [[ "$QUIET" == "true" ]]; then
        python_args="$python_args --quiet"
    fi

    # Run the Python cost monitor
    local exit_code=0
    local output=""

    if [[ "$QUIET" == "true" ]]; then
        output=$(python3 scripts/azure-cost-monitor.py $python_args 2>&1) || exit_code=$?
        echo "$output"
    else
        python3 scripts/azure-cost-monitor.py $python_args || exit_code=$?
    fi

    # Handle budget alerts and notifications
    if [[ $exit_code -eq 1 && -n "$NOTIFICATION_WEBHOOK" ]]; then
        # Budget exceeded
        local message="CRITICAL: Azure costs have exceeded the budget limit of \$$BUDGET for project $PROJECT_NAME"
        send_notification "$message" "critical"
    elif [[ -n "$NOTIFICATION_WEBHOOK" && "$QUIET" == "true" ]]; then
        # Regular notification with cost summary
        local cost_summary=$(generate_cost_summary "$output" "$BUDGET")
        send_notification "$cost_summary" "good"
    fi

    return $exit_code
}

# Generate cost summary for notifications
generate_cost_summary() {
    local cost_data="$1"
    local budget="$2"

    # Parse JSON data (simplified - in practice would use jq)
    local total_cost=$(echo "$cost_data" | grep -o '"total_cost": [0-9.]*' | cut -d' ' -f2 2>/dev/null || echo "0")
    local period=$(echo "$cost_data" | grep -o '"period": "[^"]*"' | cut -d'"' -f4 2>/dev/null || echo "Unknown")

    local summary="Cost Summary for $PROJECT_NAME"
    summary="$summary\nPeriod: $period"
    summary="$summary\nTotal Cost: \$$total_cost"

    if [[ -n "$budget" ]]; then
        local percentage=$(echo "scale=1; $total_cost * 100 / $budget" | bc -l 2>/dev/null || echo "0")
        summary="$summary\nBudget: \$$budget (${percentage}% used)"
    fi

    echo -e "$summary"
}

# Run main function with all arguments
main "$@"
