#!/bin/bash

# Azure Cost Dashboard Generator
#
# This script generates a simple HTML dashboard for monitoring Azure costs
# in real-time. It can be served via a web server or opened locally.
#
# Features:
# 1. Real-time cost monitoring dashboard
# 2. Auto-refresh capabilities
# 3. Budget alert visualization
# 4. Cost breakdown charts
# 5. Historical trend analysis
#
# Usage:
#   ./scripts/cost-dashboard.sh --project-name "my-project" --output dashboard.html
#   ./scripts/cost-dashboard.sh --serve --port 8080

set -e

# Source virtual environment utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/venv-utils.sh"

# Default configuration
PROJECT_NAME="aks-platform"
OUTPUT_FILE="cost-dashboard.html"
SERVE=false
PORT=8080
BUDGET=""
AUTO_REFRESH=300  # 5 minutes

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

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

show_help() {
    echo "Azure Cost Dashboard Generator"
    echo
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Options:"
    echo "  --project-name NAME    Project name (default: aks-platform)"
    echo "  --output FILE          Output HTML file (default: cost-dashboard.html)"
    echo "  --serve               Serve dashboard via HTTP"
    echo "  --port PORT           HTTP server port (default: 8080)"
    echo "  --budget AMOUNT       Budget limit for alerts"
    echo "  --refresh SECONDS     Auto-refresh interval (default: 300)"
    echo "  --help                Show this help message"
    echo
    echo "Examples:"
    echo "  $0 --project-name my-project --output dashboard.html"
    echo "  $0 --serve --port 8080 --budget 1000"
}

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --project-name)
                PROJECT_NAME="$2"
                shift 2
                ;;
            --output)
                OUTPUT_FILE="$2"
                shift 2
                ;;
            --serve)
                SERVE=true
                shift
                ;;
            --port)
                PORT="$2"
                shift 2
                ;;
            --budget)
                BUDGET="$2"
                shift 2
                ;;
            --refresh)
                AUTO_REFRESH="$2"
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

# Get cost data and generate dashboard
generate_dashboard() {
    print_status "Generating cost dashboard for $PROJECT_NAME..."
    
    # Get current cost data
    local cost_args="--project-name $PROJECT_NAME --current-month --export /tmp/cost-data.json"
    if [[ -n "$BUDGET" ]]; then
        cost_args="$cost_args --budget-alert $BUDGET"
    fi
    
    python3 scripts/azure-cost-monitor.py $cost_args >/dev/null 2>&1 || {
        print_error "Failed to get cost data"
        return 1
    }
    
    # Parse cost data
    local cost_data=$(cat /tmp/cost-data.json 2>/dev/null || echo '{}')
    local total_cost=$(echo "$cost_data" | jq -r '.cost_data.total_cost // 0' 2>/dev/null || echo "0")
    local period=$(echo "$cost_data" | jq -r '.cost_data.period // "Unknown"' 2>/dev/null || echo "Unknown")
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Generate budget alerts HTML
    local budget_alerts=""
    if [[ -n "$BUDGET" ]]; then
        local budget_status=$(echo "$cost_data" | jq -r '.budget_status.status // "ok"' 2>/dev/null || echo "ok")
        local percentage=$(echo "$cost_data" | jq -r '.budget_status.percentage // 0' 2>/dev/null || echo "0")
        
        case "$budget_status" in
            critical)
                budget_alerts='<div class="alert alert-critical">CRITICAL: Budget exceeded! Current cost: $'$total_cost' (Budget: $'$BUDGET')</div>'
                ;;
            warning)
                budget_alerts='<div class="alert alert-warning">WARNING: '${percentage}'% of budget used ($'$total_cost' / $'$BUDGET')</div>'
                ;;
            *)
                budget_alerts='<div class="alert alert-ok">Budget OK: '${percentage}'% used ($'$total_cost' / $'$BUDGET')</div>'
                ;;
        esac
    fi
    
    # Generate breakdown table rows
    local breakdown_rows=""
    if command -v jq >/dev/null 2>&1; then
        breakdown_rows=$(echo "$cost_data" | jq -r '
            .cost_data.breakdown // {} | 
            to_entries | 
            sort_by(.value) | 
            reverse | 
            map("<tr><td>" + .key + "</td><td class=\"cost-cell\">$" + (.value | tostring) + "</td><td>" + ((.value / ('$total_cost' + 0.01) * 100) | floor | tostring) + "%</td></tr>") | 
            join("")
        ' 2>/dev/null || echo '<tr><td colspan="3">No breakdown data available</td></tr>')
    else
        breakdown_rows='<tr><td colspan="3">jq not available for data parsing</td></tr>'
    fi
    
    # Generate HTML dashboard
    cat > "$OUTPUT_FILE" << EOF
<!DOCTYPE html>
<html>
<head>
    <title>Azure Cost Dashboard - $PROJECT_NAME</title>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background-color: #f5f5f5; }
        .container { max-width: 1200px; margin: 0 auto; }
        .header { background: #0078d4; color: white; padding: 20px; border-radius: 8px; margin-bottom: 20px; }
        .card { background: white; padding: 20px; border-radius: 8px; margin-bottom: 20px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        .cost-total { font-size: 2em; font-weight: bold; color: #0078d4; }
        .alert { padding: 15px; border-radius: 4px; margin: 10px 0; }
        .alert-critical { background-color: #f8d7da; border: 1px solid #f5c6cb; color: #721c24; }
        .alert-warning { background-color: #fff3cd; border: 1px solid #ffeaa7; color: #856404; }
        .alert-ok { background-color: #d4edda; border: 1px solid #c3e6cb; color: #155724; }
        .refresh-info { text-align: center; color: #666; margin-top: 20px; }
        table { width: 100%; border-collapse: collapse; }
        th, td { padding: 12px; text-align: left; border-bottom: 1px solid #ddd; }
        th { background-color: #f8f9fa; }
        .cost-cell { text-align: right; font-weight: bold; }
        .status-indicator { display: inline-block; width: 12px; height: 12px; border-radius: 50%; margin-right: 8px; }
        .status-ok { background-color: #28a745; }
        .status-warning { background-color: #ffc107; }
        .status-critical { background-color: #dc3545; }
    </style>
    <script>
        function refreshPage() {
            location.reload();
        }
        // Auto-refresh every ${AUTO_REFRESH} seconds
        setTimeout(refreshPage, ${AUTO_REFRESH}000);
        
        // Update timestamp
        function updateTimestamp() {
            document.getElementById('timestamp').textContent = new Date().toLocaleString();
        }
        setInterval(updateTimestamp, 1000);
    </script>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>Azure Cost Dashboard</h1>
            <p>Project: $PROJECT_NAME | Last Updated: <span id="timestamp">$timestamp</span></p>
        </div>
        
        <div class="card">
            <h2>Current Month Cost</h2>
            <div class="cost-total">\$$total_cost USD</div>
            <p>Period: $period</p>
        </div>
        
        $budget_alerts
        
        <div class="card">
            <h2>Cost Breakdown by Resource Group</h2>
            <table>
                <thead>
                    <tr>
                        <th>Resource Group</th>
                        <th>Cost (USD)</th>
                        <th>Percentage</th>
                    </tr>
                </thead>
                <tbody>
                    $breakdown_rows
                </tbody>
            </table>
        </div>
        
        <div class="card">
            <h2>Quick Actions</h2>
            <button onclick="refreshPage()" style="padding: 10px 20px; background: #0078d4; color: white; border: none; border-radius: 4px; cursor: pointer;">Refresh Now</button>
            <button onclick="window.open('https://portal.azure.com/#blade/Microsoft_Azure_CostManagement/Menu/overview', '_blank')" style="padding: 10px 20px; background: #28a745; color: white; border: none; border-radius: 4px; cursor: pointer; margin-left: 10px;">Azure Portal</button>
        </div>
        
        <div class="refresh-info">
            <p>Dashboard auto-refreshes every ${AUTO_REFRESH} seconds</p>
            <p><small>Generated by Azure Cost Monitor at $timestamp</small></p>
        </div>
    </div>
</body>
</html>
EOF

    print_success "Dashboard generated: $OUTPUT_FILE"
    
    # Clean up temporary files
    rm -f /tmp/cost-data.json
}

# Serve dashboard via HTTP
serve_dashboard() {
    print_status "Starting HTTP server on port $PORT..."
    
    # Check if Python is available
    if command -v python3 >/dev/null 2>&1; then
        print_status "Dashboard available at: http://localhost:$PORT"
        print_status "Press Ctrl+C to stop the server"
        
        # Regenerate dashboard every 5 minutes
        (
            while true; do
                sleep $AUTO_REFRESH
                generate_dashboard >/dev/null 2>&1 || true
            done
        ) &
        
        # Start HTTP server
        python3 -m http.server $PORT --bind 127.0.0.1
    else
        print_error "Python 3 not found. Cannot start HTTP server."
        print_status "You can open $OUTPUT_FILE directly in a web browser"
        exit 1
    fi
}

main() {
    parse_arguments "$@"
    
    # Check dependencies
    if [[ ! -f "scripts/azure-cost-monitor.py" ]]; then
        print_error "azure-cost-monitor.py not found"
        exit 1
    fi
    
    # Generate initial dashboard
    generate_dashboard
    
    # Serve if requested
    if [[ "$SERVE" == "true" ]]; then
        serve_dashboard
    else
        print_status "Dashboard saved to: $OUTPUT_FILE"
        print_status "Open in browser or use --serve to start HTTP server"
        
        # Try to open in default browser (macOS/Linux)
        if command -v open >/dev/null 2>&1; then
            open "$OUTPUT_FILE"
        elif command -v xdg-open >/dev/null 2>&1; then
            xdg-open "$OUTPUT_FILE"
        fi
    fi
}

main "$@"
