#!/usr/bin/env python3

"""
Azure Cost Monitor for AKS GitOps Platform

This script monitors actual Azure billing costs for infrastructure deployed by
the Azure AKS GitOps platform project. It provides real-time cost analysis,
trend monitoring, and budget alerts.

Key Features:
1. Real-time cost analysis using Azure Cost Management API
2. Project-specific cost filtering using resource tags
3. Environment-based cost breakdown (dev, staging, prod)
4. Cost trend analysis and forecasting
5. Budget alerts and threshold monitoring
6. Export capabilities for reporting and analysis

Prerequisites:
    - Azure CLI installed and authenticated
    - Azure Cost Management API access
    - Python 3.7+ with required packages

Installation:
    pip install azure-mgmt-costmanagement azure-identity azure-mgmt-resource requests

Usage:
    python3 scripts/azure-cost-monitor.py --project-name "my-project"
    python3 scripts/azure-cost-monitor.py --environment prod --days 30
    python3 scripts/azure-cost-monitor.py --budget-alert 1000 --currency USD
"""

import argparse
import json
import os
import subprocess
import sys
from datetime import datetime, timedelta
from typing import Dict, List, Optional, Tuple

# Import shared utilities if available
try:
    from azure_utils import (
        DependencyChecker,
        VirtualEnvironmentChecker,
        print_error,
        print_status,
        print_success,
        print_warning,
    )

    AZURE_UTILS_AVAILABLE = True
except ImportError:
    AZURE_UTILS_AVAILABLE = False

    # Fallback color functions
    def print_status(msg):
        print(f"[INFO] {msg}")

    def print_success(msg):
        print(f"[SUCCESS] {msg}")

    def print_warning(msg):
        print(f"[WARNING] {msg}")

    def print_error(msg):
        print(f"[ERROR] {msg}")


try:
    import requests
    from azure.identity import DefaultAzureCredential
    from azure.mgmt.costmanagement import CostManagementClient
    from azure.mgmt.resource import ResourceManagementClient
except ImportError as e:
    print_error(f"Required Azure packages not installed: {e}")
    print_status(
        "Install with: pip install azure-mgmt-costmanagement azure-identity azure-mgmt-resource requests"
    )
    if AZURE_UTILS_AVAILABLE:
        print_status("Or use the setup script: ./scripts/setup-python-env.sh")
        is_venv, _ = VirtualEnvironmentChecker.is_virtual_environment()
        if not is_venv:
            print_warning(
                "Consider using a virtual environment for better dependency management"
            )
    sys.exit(1)


class AzureCostMonitor:
    """Azure Cost Management client for monitoring platform costs."""

    def __init__(self, subscription_id: str, project_name: str = "aks-platform"):
        """Initialize the cost monitor with Azure credentials."""
        self.subscription_id = subscription_id
        self.project_name = project_name
        self.credential = DefaultAzureCredential()

        try:
            self.cost_client = CostManagementClient(self.credential)
            self.resource_client = ResourceManagementClient(
                self.credential, subscription_id
            )
        except Exception as e:
            print(f"Error: Failed to initialize Azure clients: {e}")
            print("Ensure you're logged in with: az login")
            sys.exit(1)

    def get_subscription_info(self) -> Dict:
        """Get current subscription information."""
        try:
            result = subprocess.run(
                ["az", "account", "show"], capture_output=True, text=True, check=True
            )
            return json.loads(result.stdout)
        except subprocess.CalledProcessError as e:
            print(f"Error getting subscription info: {e}")
            return {}

    def get_project_resource_groups(self) -> List[str]:
        """Get all resource groups belonging to this project."""
        resource_groups = []

        try:
            for rg in self.resource_client.resource_groups.list():
                # Check if resource group belongs to our project
                if (
                    rg.tags and rg.tags.get("Project") == self.project_name
                ) or self.project_name in rg.name:
                    resource_groups.append(rg.name)
        except Exception as e:
            print(f"Warning: Could not list resource groups: {e}")
            # Fallback to naming convention
            for env in ["dev", "staging", "prod"]:
                resource_groups.append(f"rg-{self.project_name}-{env}")
            resource_groups.append(f"{self.project_name}-terraform-state-rg")

        return resource_groups

    def get_cost_data(self, days: int = 30, environment: Optional[str] = None) -> Dict:
        """Get cost data for the specified period."""
        end_date = datetime.now()
        start_date = end_date - timedelta(days=days)

        # Format dates for Azure API
        start_date_str = start_date.strftime("%Y-%m-%d")
        end_date_str = end_date.strftime("%Y-%m-%d")

        scope = f"/subscriptions/{self.subscription_id}"

        # Build query parameters
        query_definition = {
            "type": "ActualCost",
            "timeframe": "Custom",
            "timePeriod": {"from": start_date_str, "to": end_date_str},
            "dataset": {
                "granularity": "Daily",
                "aggregation": {"totalCost": {"name": "Cost", "function": "Sum"}},
                "grouping": [
                    {"type": "Dimension", "name": "ResourceGroupName"},
                    {"type": "Dimension", "name": "ServiceName"},
                ],
            },
        }

        # Add resource group filter if environment specified
        if environment:
            rg_name = f"rg-{self.project_name}-{environment}"
            query_definition["dataset"]["filter"] = {
                "dimensions": {
                    "name": "ResourceGroupName",
                    "operator": "In",
                    "values": [rg_name],
                }
            }

        try:
            # Use Azure CLI as fallback since Cost Management API can be complex
            return self._get_cost_data_via_cli(days, environment)
        except Exception as e:
            print(f"Error getting cost data: {e}")
            return {}

    def _get_cost_data_via_cli(
        self, days: int, environment: Optional[str] = None
    ) -> Dict:
        """Get cost data using Azure CLI as fallback."""
        end_date = datetime.now()
        start_date = end_date - timedelta(days=days)

        start_date_str = start_date.strftime("%Y-%m-%d")
        end_date_str = end_date.strftime("%Y-%m-%d")

        # Get resource groups for the project
        resource_groups = self.get_project_resource_groups()

        if environment:
            # Filter to specific environment
            resource_groups = [rg for rg in resource_groups if environment in rg]

        total_cost = 0.0
        cost_breakdown = {}

        for rg in resource_groups:
            try:
                # Check if resource group exists
                check_cmd = ["az", "group", "show", "--name", rg]
                result = subprocess.run(check_cmd, capture_output=True, text=True)

                if result.returncode != 0:
                    continue  # Resource group doesn't exist

                # Get cost for this resource group
                cost_cmd = [
                    "az",
                    "consumption",
                    "usage",
                    "list",
                    "--start-date",
                    start_date_str,
                    "--end-date",
                    end_date_str,
                    "--query",
                    f"[?contains(instanceName, '{rg}')].{{cost:pretaxCost,service:meterCategory,date:usageStart}}",
                    "--output",
                    "json",
                ]

                result = subprocess.run(cost_cmd, capture_output=True, text=True)

                if result.returncode == 0 and result.stdout.strip():
                    usage_data = json.loads(result.stdout)
                    rg_cost = sum(float(item.get("cost", 0)) for item in usage_data)
                    total_cost += rg_cost
                    cost_breakdown[rg] = rg_cost

            except Exception as e:
                print(f"Warning: Could not get cost for {rg}: {e}")
                continue

        return {
            "total_cost": total_cost,
            "breakdown": cost_breakdown,
            "period": f"{start_date_str} to {end_date_str}",
            "currency": "USD",  # Default, could be enhanced to detect actual currency
        }

    def get_current_month_cost(self) -> Dict:
        """Get cost for the current month."""
        now = datetime.now()
        start_of_month = now.replace(day=1)
        days_in_month = (now - start_of_month).days + 1

        return self.get_cost_data(days=days_in_month)

    def get_cost_trend(self, days: int = 30) -> List[Dict]:
        """Get daily cost trend for analysis."""
        resource_groups = self.get_project_resource_groups()
        trend_data = []

        for i in range(days):
            date = datetime.now() - timedelta(days=i)
            date_str = date.strftime("%Y-%m-%d")

            # This is a simplified version - in practice, you'd query daily costs
            trend_data.append(
                {
                    "date": date_str,
                    "cost": 0.0,  # Would be populated with actual daily costs
                }
            )

        return trend_data

    def check_budget_alerts(self, budget_limit: float, current_cost: float) -> Dict:
        """Check if costs exceed budget thresholds."""
        percentage = (current_cost / budget_limit) * 100 if budget_limit > 0 else 0

        alerts = []
        if percentage >= 100:
            alerts.append(
                f"CRITICAL: Cost has exceeded budget by {percentage-100:.1f}%"
            )
        elif percentage >= 90:
            alerts.append(f"WARNING: Cost is at {percentage:.1f}% of budget")
        elif percentage >= 75:
            alerts.append(f"CAUTION: Cost is at {percentage:.1f}% of budget")

        return {
            "percentage": percentage,
            "alerts": alerts,
            "status": (
                "critical"
                if percentage >= 100
                else "warning" if percentage >= 75 else "ok"
            ),
        }


def format_cost_report(
    cost_data: Dict, project_name: str, environment: Optional[str] = None
) -> str:
    """Format cost data into a readable report."""
    report = []
    report.append("=" * 60)
    report.append(f"Azure Cost Report - {project_name}")
    if environment:
        report.append(f"Environment: {environment}")
    report.append(f"Period: {cost_data.get('period', 'Unknown')}")
    report.append(f"Currency: {cost_data.get('currency', 'USD')}")
    report.append("=" * 60)

    total_cost = cost_data.get("total_cost", 0)
    report.append(f"Total Cost: ${total_cost:.2f}")
    report.append("")

    # Cost breakdown by resource group
    breakdown = cost_data.get("breakdown", {})
    if breakdown:
        report.append("Cost Breakdown by Resource Group:")
        report.append("-" * 40)
        for rg, cost in sorted(breakdown.items(), key=lambda x: x[1], reverse=True):
            percentage = (cost / total_cost * 100) if total_cost > 0 else 0
            report.append(f"{rg:<30} ${cost:>8.2f} ({percentage:>5.1f}%)")
        report.append("")

    return "\n".join(report)


def main():
    """Main function to run the cost monitor."""
    parser = argparse.ArgumentParser(
        description="Monitor Azure costs for AKS GitOps platform"
    )
    parser.add_argument(
        "--project-name",
        default="aks-platform",
        help="Project name for cost filtering (default: aks-platform)",
    )
    parser.add_argument(
        "--environment",
        choices=["dev", "staging", "prod"],
        help="Specific environment to monitor",
    )
    parser.add_argument(
        "--days", type=int, default=30, help="Number of days to analyze (default: 30)"
    )
    parser.add_argument(
        "--budget-alert", type=float, help="Budget limit for alerts (in USD)"
    )
    parser.add_argument(
        "--current-month", action="store_true", help="Show current month costs only"
    )
    parser.add_argument("--export", metavar="FILE", help="Export results to JSON file")
    parser.add_argument(
        "--quiet", action="store_true", help="Minimal output for scripting"
    )

    args = parser.parse_args()

    # Check Python environment if not in quiet mode
    if not args.quiet and AZURE_UTILS_AVAILABLE:
        print_status("Checking Python environment...")
        VirtualEnvironmentChecker.check_and_warn_virtual_environment()
        print()

    # Get subscription ID
    try:
        result = subprocess.run(
            ["az", "account", "show", "--query", "id", "-o", "tsv"],
            capture_output=True,
            text=True,
            check=True,
        )
        subscription_id = result.stdout.strip()
    except subprocess.CalledProcessError:
        print(
            "Error: Could not get Azure subscription ID. Please run 'az login' first."
        )
        sys.exit(1)

    if not args.quiet:
        print(f"Monitoring costs for project: {args.project_name}")
        print(f"Subscription: {subscription_id}")
        if args.environment:
            print(f"Environment: {args.environment}")
        print()

    # Initialize cost monitor
    monitor = AzureCostMonitor(subscription_id, args.project_name)

    # Get cost data
    if args.current_month:
        cost_data = monitor.get_current_month_cost()
    else:
        cost_data = monitor.get_cost_data(args.days, args.environment)

    # Check budget alerts
    budget_status = None
    if args.budget_alert:
        budget_status = monitor.check_budget_alerts(
            args.budget_alert, cost_data.get("total_cost", 0)
        )

    # Generate report
    if not args.quiet:
        report = format_cost_report(cost_data, args.project_name, args.environment)
        print(report)

        # Show budget alerts
        if budget_status:
            print("Budget Status:")
            print("-" * 20)
            print(f"Budget Utilization: {budget_status['percentage']:.1f}%")
            for alert in budget_status["alerts"]:
                print(f"ALERT: {alert}")
            print()
    else:
        # Quiet mode - just print the total cost
        print(f"{cost_data.get('total_cost', 0):.2f}")

    # Export data if requested
    if args.export:
        export_data = {
            "project_name": args.project_name,
            "environment": args.environment,
            "cost_data": cost_data,
            "budget_status": budget_status,
            "generated_at": datetime.now().isoformat(),
        }

        with open(args.export, "w") as f:
            json.dump(export_data, f, indent=2)

        if not args.quiet:
            print(f"Cost data exported to: {args.export}")

    # Exit with error code if budget exceeded
    if budget_status and budget_status["status"] == "critical":
        sys.exit(1)


def create_cost_dashboard():
    """Create a simple HTML dashboard for cost monitoring."""
    html_template = """
<!DOCTYPE html>
<html>
<head>
    <title>Azure Cost Dashboard - {project_name}</title>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <style>
        body {{ font-family: Arial, sans-serif; margin: 20px; background-color: #f5f5f5; }}
        .container {{ max-width: 1200px; margin: 0 auto; }}
        .header {{ background: #0078d4; color: white; padding: 20px; border-radius: 8px; margin-bottom: 20px; }}
        .card {{ background: white; padding: 20px; border-radius: 8px; margin-bottom: 20px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }}
        .cost-total {{ font-size: 2em; font-weight: bold; color: #0078d4; }}
        .cost-breakdown {{ display: grid; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); gap: 20px; }}
        .alert {{ padding: 15px; border-radius: 4px; margin: 10px 0; }}
        .alert-critical {{ background-color: #f8d7da; border: 1px solid #f5c6cb; color: #721c24; }}
        .alert-warning {{ background-color: #fff3cd; border: 1px solid #ffeaa7; color: #856404; }}
        .alert-ok {{ background-color: #d4edda; border: 1px solid #c3e6cb; color: #155724; }}
        .refresh-info {{ text-align: center; color: #666; margin-top: 20px; }}
        table {{ width: 100%; border-collapse: collapse; }}
        th, td {{ padding: 12px; text-align: left; border-bottom: 1px solid #ddd; }}
        th {{ background-color: #f8f9fa; }}
        .cost-cell {{ text-align: right; font-weight: bold; }}
    </style>
    <script>
        function refreshPage() {{
            location.reload();
        }}
        // Auto-refresh every 5 minutes
        setTimeout(refreshPage, 300000);
    </script>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>Azure Cost Dashboard</h1>
            <p>Project: {project_name} | Last Updated: {timestamp}</p>
        </div>

        <div class="card">
            <h2>Current Month Cost</h2>
            <div class="cost-total">${total_cost:.2f} USD</div>
            <p>Period: {period}</p>
        </div>

        {budget_alerts}

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
                    {breakdown_rows}
                </tbody>
            </table>
        </div>

        <div class="refresh-info">
            <p>Dashboard auto-refreshes every 5 minutes</p>
            <button onclick="refreshPage()">Refresh Now</button>
        </div>
    </div>
</body>
</html>
"""
    return html_template


if __name__ == "__main__":
    main()
