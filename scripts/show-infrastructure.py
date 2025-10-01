#!/usr/bin/env python3
"""
Infrastructure Overview Script for Azure AKS Platform

This script provides a comprehensive view of all infrastructure deployed by the
Azure AKS Platform project, organized by environment and resource type.

Features:
- Lists all Azure resources by environment
- Shows Terraform state information
- Displays Kubernetes cluster details
- Cost breakdown by environment
- Service principal information
- Storage account details for Terraform state

Usage:
    python3 scripts/show-infrastructure.py [options]
    ./scripts/show-infrastructure.py --environment dev
    ./scripts/show-infrastructure.py --all-environments --include-costs
"""

import argparse
import json
import subprocess
import sys
from datetime import datetime, timedelta
from pathlib import Path
from typing import Any, Dict, List, Optional

# Import shared utilities
try:
    from azure_utils import (
        AzureHelper,
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

    # Fallback implementations
    def print_status(msg):
        print(f"[INFO] {msg}")

    def print_success(msg):
        print(f"[SUCCESS] {msg}")

    def print_warning(msg):
        print(f"[WARNING] {msg}")

    def print_error(msg):
        print(f"[ERROR] {msg}")


class InfrastructureOverview:
    """Main class for infrastructure overview functionality."""

    def __init__(self, project_name: str = "aks-platform"):
        self.project_name = project_name
        self.azure_helper = AzureHelper() if AZURE_UTILS_AVAILABLE else None

    def run_command(
        self, cmd: List[str], check: bool = True
    ) -> subprocess.CompletedProcess:
        """Run a command and return the result."""
        try:
            result = subprocess.run(cmd, capture_output=True, text=True, check=check)
            return result
        except subprocess.CalledProcessError as e:
            if check:
                print_error(f"Command failed: {' '.join(cmd)}")
                print_error(f"Error: {e.stderr}")
                raise
            return e

    def get_subscription_info(self) -> Dict[str, str]:
        """Get Azure subscription information."""
        try:
            result = self.run_command(["az", "account", "show", "--output", "json"])
            account_info = json.loads(result.stdout)
            return {
                "subscription_id": account_info["id"],
                "subscription_name": account_info["name"],
                "tenant_id": account_info["tenantId"],
            }
        except Exception as e:
            print_warning(f"Could not get subscription info: {e}")
            return {}

    def get_resource_groups(self) -> List[Dict[str, Any]]:
        """Get all resource groups related to the project."""
        try:
            result = self.run_command(
                [
                    "az",
                    "group",
                    "list",
                    "--query",
                    f"[?contains(name, '{self.project_name}')]",
                    "--output",
                    "json",
                ]
            )
            return json.loads(result.stdout)
        except Exception as e:
            print_warning(f"Could not get resource groups: {e}")
            return []

    def get_resources_in_group(self, resource_group: str) -> List[Dict[str, Any]]:
        """Get all resources in a specific resource group."""
        try:
            result = self.run_command(
                [
                    "az",
                    "resource",
                    "list",
                    "--resource-group",
                    resource_group,
                    "--output",
                    "json",
                ]
            )
            return json.loads(result.stdout)
        except Exception as e:
            print_warning(f"Could not get resources for {resource_group}: {e}")
            return []

    def get_aks_clusters(self) -> List[Dict[str, Any]]:
        """Get all AKS clusters related to the project."""
        try:
            result = self.run_command(
                [
                    "az",
                    "aks",
                    "list",
                    "--query",
                    f"[?contains(name, '{self.project_name}')]",
                    "--output",
                    "json",
                ]
            )
            return json.loads(result.stdout)
        except Exception as e:
            print_warning(f"Could not get AKS clusters: {e}")
            return []

    def get_storage_accounts(self) -> List[Dict[str, Any]]:
        """Get all storage accounts related to the project."""
        try:
            result = self.run_command(
                [
                    "az",
                    "storage",
                    "account",
                    "list",
                    "--query",
                    f"[?contains(name, '{self.project_name.replace('-', '')}')]",
                    "--output",
                    "json",
                ]
            )
            return json.loads(result.stdout)
        except Exception as e:
            print_warning(f"Could not get storage accounts: {e}")
            return []

    def get_service_principals(self) -> List[Dict[str, Any]]:
        """Get all service principals related to the project."""
        try:
            result = self.run_command(
                [
                    "az",
                    "ad",
                    "sp",
                    "list",
                    "--query",
                    f"[?contains(displayName, '{self.project_name}')]",
                    "--output",
                    "json",
                ]
            )
            return json.loads(result.stdout)
        except Exception as e:
            print_warning(f"Could not get service principals: {e}")
            return []

    def get_terraform_state_info(self, environment: str) -> Dict[str, Any]:
        """Get Terraform state information for an environment."""
        terraform_dir = Path(f"terraform")
        env_dir = terraform_dir / "environments" / environment

        if not env_dir.exists():
            return {"error": f"Environment directory not found: {env_dir}"}

        info = {
            "environment": environment,
            "terraform_dir": str(env_dir),
            "backend_config_exists": (env_dir / "backend.conf").exists(),
            "tfvars_exists": (env_dir / "terraform.tfvars").exists(),
            "state_info": {},
        }

        # Try to get Terraform state info
        if info["backend_config_exists"]:
            try:
                original_dir = Path.cwd()
                terraform_dir.mkdir(exist_ok=True)
                subprocess.run(
                    [
                        "terraform",
                        "init",
                        f"-backend-config=environments/{environment}/backend.conf",
                    ],
                    cwd=terraform_dir,
                    capture_output=True,
                    check=False,
                )

                result = subprocess.run(
                    ["terraform", "show", "-json"],
                    cwd=terraform_dir,
                    capture_output=True,
                    text=True,
                )
                if result.returncode == 0:
                    state_data = json.loads(result.stdout)
                    info["state_info"] = {
                        "terraform_version": state_data.get("terraform_version"),
                        "resource_count": len(
                            state_data.get("values", {})
                            .get("root_module", {})
                            .get("resources", [])
                        ),
                        "last_modified": "Available in state",
                    }
            except Exception as e:
                info["state_info"] = {"error": str(e)}

        return info

    def get_environment_costs(self, environment: str, days: int = 30) -> Dict[str, Any]:
        """Get cost information for an environment."""
        end_date = datetime.now()
        start_date = end_date - timedelta(days=days)

        try:
            result = self.run_command(
                [
                    "az",
                    "consumption",
                    "usage",
                    "list",
                    "--start-date",
                    start_date.strftime("%Y-%m-%d"),
                    "--end-date",
                    end_date.strftime("%Y-%m-%d"),
                    "--query",
                    f"[?contains(instanceName, '{self.project_name}-{environment}')]",
                    "--output",
                    "json",
                ],
                check=False,
            )

            if result.returncode == 0:
                usage_data = json.loads(result.stdout)
                total_cost = sum(
                    float(item.get("pretaxCost", 0)) for item in usage_data
                )
                return {
                    "total_cost": total_cost,
                    "currency": "USD",
                    "period_days": days,
                    "resource_count": len(usage_data),
                }
        except Exception as e:
            return {"error": f"Cost data unavailable: {e}"}

        return {"error": "Cost data unavailable"}

    def get_github_secrets(self) -> Dict[str, Any]:
        """Get GitHub repository secrets information."""
        try:
            result = self.run_command(
                ["gh", "secret", "list", "--json", "name,visibility"], check=False
            )
            if result.returncode == 0:
                secrets = json.loads(result.stdout)
                return {
                    "repository_secrets": [s["name"] for s in secrets],
                    "secret_count": len(secrets),
                }
        except Exception as e:
            return {"error": f"Could not get GitHub secrets: {e}"}

        return {"error": "GitHub CLI not available or not authenticated"}

    def get_github_environment_secrets(self, environment: str) -> Dict[str, Any]:
        """Get GitHub environment-specific secrets and variables."""
        try:
            # Get environment secrets
            secrets_result = self.run_command(
                ["gh", "secret", "list", "--env", environment, "--json", "name"],
                check=False,
            )

            # Get environment variables
            vars_result = self.run_command(
                ["gh", "variable", "list", "--env", environment, "--json", "name"],
                check=False,
            )

            env_info = {"environment": environment}

            if secrets_result.returncode == 0:
                secrets = json.loads(secrets_result.stdout)
                env_info["secrets"] = [s["name"] for s in secrets]
                env_info["secret_count"] = len(secrets)
            else:
                env_info["secrets"] = []
                env_info["secret_count"] = 0
                env_info["secrets_error"] = "Could not retrieve secrets"

            if vars_result.returncode == 0:
                variables = json.loads(vars_result.stdout)
                env_info["variables"] = [v["name"] for v in variables]
                env_info["variable_count"] = len(variables)
            else:
                env_info["variables"] = []
                env_info["variable_count"] = 0
                env_info["variables_error"] = "Could not retrieve variables"

            return env_info

        except Exception as e:
            return {
                "environment": environment,
                "error": f"Could not get GitHub environment info: {e}",
            }

    def check_github_environment_exists(self, environment: str) -> bool:
        """Check if a GitHub environment exists."""
        try:
            result = self.run_command(
                ["gh", "api", f"/repos/{{owner}}/{{repo}}/environments/{environment}"],
                check=False,
            )
            return result.returncode == 0
        except Exception:
            return False

    def display_overview(self, environments: List[str], include_costs: bool = False):
        """Display comprehensive infrastructure overview."""
        print("=" * 80)
        print(f"INFRASTRUCTURE OVERVIEW - {self.project_name.upper()}")
        print("=" * 80)
        print()

        # Subscription info
        sub_info = self.get_subscription_info()
        if sub_info:
            print("AZURE SUBSCRIPTION")
            print("-" * 40)
            print(f"Name: {sub_info.get('subscription_name', 'Unknown')}")
            print(f"ID: {sub_info.get('subscription_id', 'Unknown')}")
            print(f"Tenant: {sub_info.get('tenant_id', 'Unknown')}")
            print()

        # Resource Groups
        resource_groups = self.get_resource_groups()
        if resource_groups:
            print("RESOURCE GROUPS")
            print("-" * 40)
            for rg in resource_groups:
                location = rg.get("location", "Unknown")
                status = rg.get("properties", {}).get("provisioningState", "Unknown")
                print(f"• {rg['name']} ({location}) - {status}")
            print()

        # Service Principals
        service_principals = self.get_service_principals()
        if service_principals:
            print("SERVICE PRINCIPALS")
            print("-" * 40)
            for sp in service_principals:
                app_id = sp.get("appId", "Unknown")
                enabled = "ENABLED" if sp.get("accountEnabled") else "DISABLED"
                print(f"• {sp['displayName']} ({app_id}) - {enabled}")
            print()

        # Storage Accounts (Terraform State)
        storage_accounts = self.get_storage_accounts()
        if storage_accounts:
            print("TERRAFORM STATE STORAGE")
            print("-" * 40)
            for sa in storage_accounts:
                location = sa.get("location", "Unknown")
                tier = sa.get("sku", {}).get("tier", "Unknown")
                print(f"• {sa['name']} ({location}) - {tier}")
            print()

        # GitHub Repository Secrets
        github_secrets = self.get_github_secrets()
        print("GITHUB REPOSITORY SECRETS")
        print("-" * 40)
        if "error" in github_secrets:
            print(f"ERROR: {github_secrets['error']}")
        else:
            print(f"Repository secrets: {github_secrets['secret_count']}")
            if github_secrets["repository_secrets"]:
                for secret in github_secrets["repository_secrets"]:
                    print(f"• {secret}")
            else:
                print("• No repository secrets found")
        print()

        # Environment-specific details
        for env in environments:
            self.display_environment_details(env, include_costs)

    def display_environment_details(
        self, environment: str, include_costs: bool = False
    ):
        """Display detailed information for a specific environment."""
        print(f"ENVIRONMENT: {environment.upper()}")
        print("=" * 60)

        # Terraform state info
        tf_info = self.get_terraform_state_info(environment)
        print("Terraform State")
        print("-" * 30)
        if "error" in tf_info:
            print(f"ERROR: {tf_info['error']}")
        else:
            print(
                f"Backend Config: {'YES' if tf_info['backend_config_exists'] else 'NO'}"
            )
            print(f"Variables File: {'YES' if tf_info['tfvars_exists'] else 'NO'}")
            if tf_info["state_info"]:
                if "error" in tf_info["state_info"]:
                    print(f"State: ERROR - {tf_info['state_info']['error']}")
                else:
                    print(
                        f"Resources: {tf_info['state_info'].get('resource_count', 0)}"
                    )
                    print(
                        f"TF Version: {tf_info['state_info'].get('terraform_version', 'Unknown')}"
                    )
        print()

        # AKS Clusters
        aks_clusters = [
            cluster
            for cluster in self.get_aks_clusters()
            if environment in cluster.get("name", "")
        ]
        if aks_clusters:
            print("AKS Clusters")
            print("-" * 30)
            for cluster in aks_clusters:
                status = cluster.get("powerState", {}).get("code", "Unknown")
                node_count = cluster.get("agentPoolProfiles", [{}])[0].get("count", 0)
                k8s_version = cluster.get("kubernetesVersion", "Unknown")
                print(f"• {cluster['name']}")
                print(f"  Status: {status}")
                print(f"  Nodes: {node_count}")
                print(f"  K8s Version: {k8s_version}")
                print(f"  Location: {cluster.get('location', 'Unknown')}")
        else:
            print("AKS Clusters: None found")
        print()

        # Environment-specific resource groups
        env_resource_groups = [
            rg for rg in self.get_resource_groups() if environment in rg.get("name", "")
        ]

        for rg in env_resource_groups:
            resources = self.get_resources_in_group(rg["name"])
            if resources:
                print(f"Resources in {rg['name']}")
                print("-" * 50)

                # Group resources by type
                resource_types = {}
                for resource in resources:
                    res_type = resource.get("type", "Unknown")
                    if res_type not in resource_types:
                        resource_types[res_type] = []
                    resource_types[res_type].append(resource)

                for res_type, res_list in resource_types.items():
                    print(f"  {res_type}: {len(res_list)} resources")
                    for resource in res_list[:3]:  # Show first 3 resources
                        print(f"    • {resource.get('name', 'Unknown')}")
                    if len(res_list) > 3:
                        print(f"    ... and {len(res_list) - 3} more")
                print()

        # GitHub Environment Configuration
        print("GitHub Environment")
        print("-" * 30)

        env_exists = self.check_github_environment_exists(environment)
        if env_exists:
            print(f"Environment exists: YES")

            github_env_info = self.get_github_environment_secrets(environment)
            if "error" in github_env_info:
                print(f"ERROR: {github_env_info['error']}")
            else:
                print(f"Secrets: {github_env_info['secret_count']}")
                if github_env_info["secrets"]:
                    for secret in github_env_info["secrets"]:
                        print(f"  • {secret}")

                print(f"Variables: {github_env_info['variable_count']}")
                if github_env_info["variables"]:
                    for variable in github_env_info["variables"]:
                        print(f"  • {variable}")

                if (
                    github_env_info["secret_count"] == 0
                    and github_env_info["variable_count"] == 0
                ):
                    print("WARNING: No secrets or variables configured")
        else:
            print(f"Environment exists: NO")
            print("WARNING: GitHub environment not created")
            print("Run: ./scripts/setup-github-secrets.sh")
        print()

        # Cost information
        if include_costs:
            cost_info = self.get_environment_costs(environment)
            print("Cost Information (Last 30 days)")
            print("-" * 40)
            if "error" in cost_info:
                print(f"ERROR: {cost_info['error']}")
            else:
                print(
                    f"Total Cost: ${cost_info['total_cost']:.2f} {cost_info['currency']}"
                )
                print(f"Resources: {cost_info['resource_count']}")
            print()

        print()


def main():
    """Main function."""
    parser = argparse.ArgumentParser(
        description="Show infrastructure overview for Azure AKS Platform"
    )
    parser.add_argument(
        "--project-name",
        default="aks-platform",
        help="Project name (default: aks-platform)",
    )
    parser.add_argument(
        "--environment", help="Show details for specific environment only"
    )
    parser.add_argument(
        "--all-environments",
        action="store_true",
        help="Show details for all environments (dev, staging, prod)",
    )
    parser.add_argument(
        "--include-costs",
        action="store_true",
        help="Include cost information (requires Azure consumption API access)",
    )
    parser.add_argument(
        "--output-format",
        choices=["text", "json"],
        default="text",
        help="Output format (default: text)",
    )

    args = parser.parse_args()

    # Determine environments to show
    if args.environment:
        environments = [args.environment]
    elif args.all_environments:
        environments = ["dev", "staging", "prod"]
    else:
        environments = ["dev"]  # Default to dev only

    print_status(f"Gathering infrastructure information for: {', '.join(environments)}")
    print()

    # Check Python environment
    if AZURE_UTILS_AVAILABLE:
        print_status("Checking Python environment...")
        VirtualEnvironmentChecker.check_python_version()
        VirtualEnvironmentChecker.check_and_warn_virtual_environment()
        print()

    try:
        overview = InfrastructureOverview(args.project_name)

        if args.output_format == "json":
            # TODO: Implement JSON output format
            print_warning("JSON output format not yet implemented, using text format")

        overview.display_overview(environments, args.include_costs)

        print_success("Infrastructure overview completed!")

    except KeyboardInterrupt:
        print_error("Operation cancelled by user")
        sys.exit(1)
    except Exception as e:
        print_error(f"An error occurred: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
