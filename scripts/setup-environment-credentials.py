#!/usr/bin/env python3
"""
Environment-Specific Azure Credentials Setup Script

This script creates separate Azure service principals and credentials for each
environment (dev, staging, prod), enabling proper isolation and security.

Key Features:
1. Environment-Specific Service Principals:
   - Creates dedicated service principals per environment
   - Assigns appropriate RBAC permissions per environment
   - Generates separate credentials for each environment

2. GitHub Environment Integration:
   - Sets up environment-specific secrets in GitHub
   - Configures environment-specific variables
   - Supports different Azure subscriptions per environment

3. Multi-Tenant Support:
   - Supports different Azure tenants per environment
   - Handles cross-subscription deployments
   - Manages environment-specific resource scoping

Usage:
    python3 scripts/setup-environment-credentials.py [options]
    ./scripts/setup-environment-credentials.py --environment dev
    ./scripts/setup-environment-credentials.py --all-environments
"""

import argparse
import json
import os
import subprocess
import sys
import time
from pathlib import Path
from typing import Dict, List, Optional

# Import shared utilities if available
try:
    from azure_utils import (
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


class EnvironmentCredentialsSetup:
    """Main class for environment-specific credentials setup."""

    def __init__(self, project_name: str = "aks-platform"):
        self.project_name = project_name
        self.environments = {}

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
                sys.exit(1)
            return e

    def get_subscription_info(self) -> Dict[str, str]:
        """Get current Azure subscription information."""
        result = self.run_command(["az", "account", "show", "--output", "json"])
        account_info = json.loads(result.stdout)
        return {
            "subscription_id": account_info["id"],
            "subscription_name": account_info["name"],
            "tenant_id": account_info["tenantId"],
        }

    def create_environment_service_principal(
        self, environment: str, subscription_id: str
    ) -> Dict[str, str]:
        """Create environment-specific service principal."""
        sp_name = f"{self.project_name}-{environment}-sp"

        print_status(
            f"Creating service principal for {environment} environment: {sp_name}"
        )

        # Check if service principal exists
        result = self.run_command(
            [
                "az",
                "ad",
                "sp",
                "list",
                "--display-name",
                sp_name,
                "--query",
                "[0].appId",
                "--output",
                "tsv",
            ],
            check=False,
        )

        if result.stdout.strip():
            print_warning(f"Service principal {sp_name} already exists")
            app_id = result.stdout.strip()

            # Get existing credentials (this will require manual intervention)
            print_warning(
                f"Using existing service principal. You may need to reset credentials."
            )
            return {"app_id": app_id, "existing": True}

        # Create service principal with environment-specific scope
        scope = f"/subscriptions/{subscription_id}"

        result = self.run_command(
            [
                "az",
                "ad",
                "sp",
                "create-for-rbac",
                "--name",
                sp_name,
                "--role",
                "Contributor",
                "--scopes",
                scope,
                "--sdk-auth",
            ]
        )

        sp_info = json.loads(result.stdout)

        print_success(f"Created service principal: {sp_name}")
        print_success(f"Application ID: {sp_info['clientId']}")

        # Assign additional roles for environment
        self.assign_environment_roles(sp_info["clientId"], subscription_id, environment)

        return sp_info

    def assign_environment_roles(
        self, app_id: str, subscription_id: str, environment: str
    ):
        """Assign environment-appropriate roles to service principal."""
        print_status(f"Assigning roles for {environment} environment...")

        # Base roles for all environments
        base_roles = ["User Access Administrator", "Key Vault Administrator"]

        # Environment-specific roles
        env_roles = {
            "dev": ["Storage Account Contributor"],
            "staging": ["Storage Account Contributor", "Network Contributor"],
            "prod": [
                "Storage Account Contributor",
                "Network Contributor",
                "Security Admin",
            ],
        }

        all_roles = base_roles + env_roles.get(environment, [])

        for role in all_roles:
            result = self.run_command(
                [
                    "az",
                    "role",
                    "assignment",
                    "create",
                    "--assignee",
                    app_id,
                    "--role",
                    role,
                    "--scope",
                    f"/subscriptions/{subscription_id}",
                ],
                check=False,
            )

            if result.returncode == 0:
                print_success(f"Assigned role: {role}")
            else:
                print_warning(f"Failed to assign role {role} (may already exist)")

    def setup_environment_credentials(
        self, environment: str, subscription_id: str = None
    ) -> Dict[str, str]:
        """Set up credentials for a specific environment."""
        print_status(f"Setting up credentials for {environment} environment...")

        # Use current subscription if not specified
        if not subscription_id:
            sub_info = self.get_subscription_info()
            subscription_id = sub_info["subscription_id"]

        # Create environment-specific service principal
        sp_info = self.create_environment_service_principal(
            environment, subscription_id
        )

        # Store environment configuration
        self.environments[environment] = {
            "subscription_id": subscription_id,
            "service_principal": sp_info,
            "credentials_file": f"github-actions-credentials-{environment}.json",
        }

        # Generate environment-specific credentials file
        if not sp_info.get("existing"):
            self.generate_environment_credentials_file(environment, sp_info)

        return sp_info

    def generate_environment_credentials_file(
        self, environment: str, sp_info: Dict[str, str]
    ):
        """Generate GitHub Actions credentials file for environment."""
        credentials_file = f"github-actions-credentials-{environment}.json"

        print_status(f"Generating credentials file: {credentials_file}")

        with open(credentials_file, "w") as f:
            json.dump(sp_info, f, indent=2)

        print_success(f"Generated {credentials_file}")
        print_warning(
            f"Keep {credentials_file} secure - it contains sensitive credentials"
        )

    def setup_github_environment_secrets(self, environment: str):
        """Set up GitHub environment-specific secrets."""
        if environment not in self.environments:
            print_error(f"Environment {environment} not configured")
            return

        env_config = self.environments[environment]
        sp_info = env_config["service_principal"]

        print_status(f"Setting up GitHub secrets for {environment} environment...")

        # Check if GitHub CLI is available
        result = self.run_command(["which", "gh"], check=False)
        if result.returncode != 0:
            print_warning("GitHub CLI not found. Skipping GitHub setup.")
            return

        # Set environment-specific secrets
        secrets = {
            "ARM_CLIENT_ID": sp_info.get("clientId", sp_info.get("app_id")),
            "ARM_CLIENT_SECRET": sp_info.get("clientSecret", ""),
            "ARM_SUBSCRIPTION_ID": env_config["subscription_id"],
            "ARM_TENANT_ID": sp_info.get("tenantId", ""),
        }

        for secret_name, secret_value in secrets.items():
            if secret_value:
                result = self.run_command(
                    [
                        "gh",
                        "secret",
                        "set",
                        secret_name,
                        "--env",
                        environment,
                        "--body",
                        secret_value,
                    ],
                    check=False,
                )

                if result.returncode == 0:
                    print_success(f"Set {secret_name} for {environment}")
                else:
                    print_warning(f"Failed to set {secret_name} for {environment}")

        # Set AZURE_CREDENTIALS from file if it exists
        credentials_file = env_config["credentials_file"]
        if os.path.exists(credentials_file):
            result = self.run_command(
                ["gh", "secret", "set", "AZURE_CREDENTIALS", "--env", environment],
                input=open(credentials_file).read(),
                check=False,
            )

            if result.returncode == 0:
                print_success(f"Set AZURE_CREDENTIALS for {environment}")

        # Set environment variables
        variables = {
            "ENVIRONMENT": environment,
            "CLUSTER_NAME": f"{self.project_name}-{environment}",
            "PROJECT_NAME": self.project_name,
        }

        for var_name, var_value in variables.items():
            result = self.run_command(
                [
                    "gh",
                    "variable",
                    "set",
                    var_name,
                    "--env",
                    environment,
                    "--body",
                    var_value,
                ],
                check=False,
            )

            if result.returncode == 0:
                print_success(f"Set variable {var_name} for {environment}")
            else:
                print_warning(f"Failed to set variable {var_name} for {environment}")


def main():
    """Main function."""
    parser = argparse.ArgumentParser(
        description="Setup environment-specific Azure credentials"
    )
    parser.add_argument(
        "--project-name",
        default="aks-platform",
        help="Project name (default: aks-platform)",
    )
    parser.add_argument(
        "--environment", help="Setup specific environment only (dev, staging, prod)"
    )
    parser.add_argument(
        "--all-environments",
        action="store_true",
        help="Setup all environments (dev, staging, prod)",
    )
    parser.add_argument(
        "--skip-github", action="store_true", help="Skip GitHub secrets setup"
    )

    args = parser.parse_args()

    # Determine environments to setup
    if args.environment:
        environments = [args.environment]
    elif args.all_environments:
        environments = ["dev", "staging", "prod"]
    else:
        environments = ["dev"]  # Default to dev only

    print_status(
        f"Setting up environment-specific credentials for: {', '.join(environments)}"
    )

    # Check Python environment
    if AZURE_UTILS_AVAILABLE:
        VirtualEnvironmentChecker.check_and_warn_virtual_environment()

    try:
        setup = EnvironmentCredentialsSetup(args.project_name)

        for env in environments:
            print_status(f"Processing {env} environment...")
            setup.setup_environment_credentials(env)

            if not args.skip_github:
                setup.setup_github_environment_secrets(env)

            print_success(f"Completed setup for {env} environment")
            print()

        print_success("Environment-specific credentials setup completed!")

        print_status("Next steps:")
        print("1. Review generated credentials files")
        print("2. Test GitHub Actions workflows")
        print("3. Configure environment protection rules in GitHub")
        print("4. Set up different Azure subscriptions for staging/prod if needed")

    except KeyboardInterrupt:
        print_error("Setup cancelled by user")
        sys.exit(1)
    except Exception as e:
        print_error(f"Setup failed: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
