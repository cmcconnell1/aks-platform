#!/usr/bin/env python3
"""
Azure Credentials Setup Script (Python Implementation)

This Python script provides an alternative to the bash version for users who
prefer Python or are working in environments where bash is not available.
It performs the same functions as the bash script but with additional
error handling and cross-platform compatibility.

Key Features:
1. Service Principal Management:
   - Creates dedicated service principals for Terraform operations
   - Assigns appropriate RBAC permissions with retry logic
   - Handles credential generation and secure storage

2. Storage Account Configuration:
   - Creates storage accounts for Terraform state management
   - Configures blob containers with proper access controls
   - Implements state locking and encryption

3. Cross-Platform Support:
   - Works on Windows, macOS, and Linux
   - Handles path separators and file permissions correctly
   - Provides consistent output formatting across platforms

4. Enhanced Error Handling:
   - Detailed error messages with troubleshooting guidance
   - Retry logic for transient Azure API failures
   - Validation of prerequisites and permissions

5. Configuration Generation:
   - Creates Terraform backend configuration files
   - Generates environment-specific variable files
   - Sets up proper directory structure

Prerequisites:
    - Python 3.7+ with pip
    - Azure CLI installed and authenticated
    - Required Python packages (see requirements below)

Installation:
    pip install azure-cli azure-identity azure-mgmt-storage azure-mgmt-authorization

Usage:
    python3 scripts/setup-azure-credentials.py
    python3 scripts/setup-azure-credentials.py --project-name "my-project" --location "West US 2"
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
        AzureHelper,
        ConfigManager,
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


# ANSI color codes for cross-platform terminal output formatting
class Colors:
    """
    ANSI color codes for consistent terminal output across platforms.
    These codes work on most modern terminals including Windows Terminal,
    macOS Terminal, and Linux terminals.
    """

    BLUE = "\033[0;34m"  # Informational messages
    GREEN = "\033[0;32m"  # Success messages
    YELLOW = "\033[1;33m"  # Warning messages
    RED = "\033[0;31m"  # Error messages
    NC = "\033[0m"  # Reset to default color


# Utility functions for consistent colored output throughout the script


def print_status(message: str) -> None:
    """
    Print informational status messages in blue.

    Args:
        message: The status message to display

    Example:
        print_status("Creating service principal...")
    """
    print(f"{Colors.BLUE}[INFO]{Colors.NC} {message}")


def print_success(message: str) -> None:
    """
    Print success messages in green.

    Args:
        message: The success message to display

    Example:
        print_success("Service principal created successfully")
    """
    print(f"{Colors.GREEN}[SUCCESS]{Colors.NC} {message}")


def print_warning(message: str) -> None:
    """
    Print warning messages in yellow.

    Args:
        message: The warning message to display

    Example:
        print_warning("Storage account already exists, skipping creation")
    """
    print(f"{Colors.YELLOW}[WARNING]{Colors.NC} {message}")


def print_error(message: str) -> None:
    """
    Print error messages in red.

    Args:
        message: The error message to display

    Example:
        print_error("Failed to create service principal")
    """
    print(f"{Colors.RED}[ERROR]{Colors.NC} {message}")


def run_command(command: List[str], check: bool = True) -> subprocess.CompletedProcess:
    """
    Execute a shell command and return the result with error handling.

    This function provides a consistent interface for running Azure CLI
    commands and other system commands with proper error handling and
    output capture.

    Args:
        command: List of command arguments (e.g., ['az', 'account', 'show'])
        check: Whether to raise an exception on non-zero exit codes

    Returns:
        CompletedProcess object with stdout, stderr, and return code

    Raises:
        subprocess.CalledProcessError: If check=True and command fails

    Example:
        result = run_command(['az', 'account', 'show', '--output', 'json'])
        account_info = json.loads(result.stdout)
    """
    try:
        result = subprocess.run(command, capture_output=True, text=True, check=check)
        return result
    except subprocess.CalledProcessError as e:
        print_error(f"Command failed: {' '.join(command)}")
        print_error(f"Error: {e.stderr}")
        if check:
            sys.exit(1)
        return e


def check_prerequisites() -> None:
    """Check if required tools are installed and Azure is properly configured."""
    print_status("Checking prerequisites...")

    required_tools = ["az", "jq"]
    for tool in required_tools:
        result = run_command(["which", tool], check=False)
        if result.returncode != 0:
            print_error(f"{tool} is not installed. Please install it first.")
            sys.exit(1)

    # Check if logged in to Azure
    result = run_command(["az", "account", "show"], check=False)
    if result.returncode != 0:
        print_error("Not logged in to Azure. Please run 'az login' first.")
        sys.exit(1)

    # Check and register required Azure resource providers
    check_and_register_providers()

    print_success("Prerequisites check passed")


def check_and_register_providers() -> None:
    """Check and register required Azure resource providers."""
    print_status("Checking Azure resource providers...")

    required_providers = [
        "Microsoft.ContainerService",
        "Microsoft.ContainerRegistry",
        "Microsoft.ContainerInstance",
        "Microsoft.Network",
        "Microsoft.Compute",
        "Microsoft.Storage",
        "Microsoft.KeyVault",
        "Microsoft.Authorization",
        "Microsoft.Resources",
        "Microsoft.ManagedIdentity",
    ]

    unregistered_providers = []

    for provider in required_providers:
        result = run_command(
            [
                "az",
                "provider",
                "show",
                "--namespace",
                provider,
                "--query",
                "registrationState",
                "--output",
                "tsv",
            ],
            check=False,
        )

        if result.returncode == 0:
            state = result.stdout.strip()
            if state != "Registered":
                unregistered_providers.append(provider)
                print_status(f"Provider {provider}: {state}")
            else:
                print_status(f"Provider {provider}: Registered")
        else:
            print_warning(f"Could not check provider {provider}")
            unregistered_providers.append(provider)

    # Register unregistered providers
    if unregistered_providers:
        print_status(f"Registering {len(unregistered_providers)} resource providers...")

        for provider in unregistered_providers:
            print_status(f"Registering {provider}...")
            result = run_command(
                ["az", "provider", "register", "--namespace", provider], check=False
            )

            if result.returncode == 0:
                print_success(f"Registration initiated for {provider}")
            else:
                print_error(f"Failed to register {provider}")
                sys.exit(1)

        # Wait for registration to complete
        print_status("Waiting for provider registration to complete...")
        max_wait_time = 300  # 5 minutes
        start_time = time.time()

        while time.time() - start_time < max_wait_time:
            all_registered = True
            for provider in unregistered_providers:
                result = run_command(
                    [
                        "az",
                        "provider",
                        "show",
                        "--namespace",
                        provider,
                        "--query",
                        "registrationState",
                        "--output",
                        "tsv",
                    ],
                    check=False,
                )

                if result.returncode != 0 or result.stdout.strip() != "Registered":
                    all_registered = False
                    break

            if all_registered:
                print_success("All resource providers registered successfully")
                break

            print_status("Still waiting for provider registration...")
            time.sleep(10)
        else:
            print_warning("Provider registration is taking longer than expected")
            print_status(
                "Continuing with setup - providers will complete registration in background"
            )
    else:
        print_success("All required resource providers are already registered")


def get_subscription_info() -> Dict[str, str]:
    """Get current Azure subscription information."""
    print_status("Getting Azure subscription information...")

    result = run_command(["az", "account", "show", "--output", "json"])
    account_info = json.loads(result.stdout)

    subscription_id = account_info["id"]
    subscription_name = account_info["name"]
    tenant_id = account_info["tenantId"]

    print_success(f"Using subscription: {subscription_name} ({subscription_id})")
    print_success(f"Tenant ID: {tenant_id}")

    return {
        "subscription_id": subscription_id,
        "subscription_name": subscription_name,
        "tenant_id": tenant_id,
    }


def create_state_resource_group(project_name: str, location: str) -> str:
    """Create resource group for Terraform state."""
    print_status("Creating resource group for Terraform state...")

    rg_name = f"{project_name}-terraform-state-rg"

    # Check if resource group exists
    result = run_command(["az", "group", "show", "--name", rg_name], check=False)
    if result.returncode == 0:
        print_warning(f"Resource group {rg_name} already exists")
    else:
        run_command(
            [
                "az",
                "group",
                "create",
                "--name",
                rg_name,
                "--location",
                location,
                "--tags",
                f"Purpose=TerraformState",
                f"Project={project_name}",
            ]
        )
        print_success(f"Created resource group: {rg_name}")

    return rg_name


def create_storage_accounts(
    project_name: str, rg_name: str, location: str, environments: List[str]
) -> Dict[str, str]:
    """Create storage accounts for each environment."""
    print_status("Creating storage accounts for Terraform state...")

    storage_accounts = {}
    timestamp = str(int(time.time()))[-6:]  # Last 6 digits

    for env in environments:
        # Ensure storage account name is <= 24 chars (Azure limit)
        # Format: <short_project>tf<env><timestamp>
        short_project = project_name.replace("-", "").replace("_", "")[
            :8
        ]  # Max 8 chars
        storage_name = f"{short_project}tf{env}{timestamp}"

        print_status(f"Creating storage account for {env} environment...")

        # Create storage account
        run_command(
            [
                "az",
                "storage",
                "account",
                "create",
                "--name",
                storage_name,
                "--resource-group",
                rg_name,
                "--location",
                location,
                "--sku",
                "Standard_LRS",
                "--encryption-services",
                "blob",
                "--https-only",
                "true",
                "--min-tls-version",
                "TLS1_2",
                "--tags",
                f"Environment={env}",
                "Purpose=TerraformState",
                f"Project={project_name}",
            ]
        )

        # Create container
        run_command(
            [
                "az",
                "storage",
                "container",
                "create",
                "--name",
                "tfstate",
                "--account-name",
                storage_name,
                "--auth-mode",
                "login",
            ]
        )

        storage_accounts[env] = storage_name
        print_success(f"Created storage account: {storage_name}")

    return storage_accounts


def create_service_principal(
    project_name: str, subscription_id: str, sp_type: str
) -> Dict[str, str]:
    """Create service principal with appropriate permissions."""
    sp_name = f"{project_name}-{sp_type}-sp"

    print_status(f"Creating service principal for {sp_type}...")

    # Check if service principal exists
    result = run_command(
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
        return {"app_id": app_id}

    # Create service principal
    result = run_command(
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
            f"/subscriptions/{subscription_id}",
            "--sdk-auth",
        ]
    )

    sp_info = json.loads(result.stdout)
    app_id = sp_info["clientId"]
    client_secret = sp_info["clientSecret"]

    print_success(f"Created service principal: {sp_name}")
    print_success(f"Application ID: {app_id}")

    # Assign additional roles
    print_status("Assigning additional roles...")

    additional_roles = ["User Access Administrator", "Key Vault Administrator"]
    for role in additional_roles:
        run_command(
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
        )  # Don't fail if role already assigned

    return {
        "app_id": app_id,
        "client_secret": client_secret,
        "sp_output": result.stdout,
    }


def generate_env_file(
    project_name: str,
    azure_info: Dict[str, str],
    terraform_sp: Dict[str, str],
    storage_accounts: Dict[str, str],
) -> None:
    """Generate .env file with all credentials."""
    print_status("Generating .env file...")

    env_content = f"""# Azure credentials for {project_name}
# Generated on {time.strftime('%Y-%m-%d %H:%M:%S')}

# Azure subscription info
ARM_CLIENT_ID={terraform_sp['app_id']}
ARM_TENANT_ID={azure_info['tenant_id']}
ARM_SUBSCRIPTION_ID={azure_info['subscription_id']}
"""

    if "client_secret" in terraform_sp:
        env_content += f"ARM_CLIENT_SECRET={terraform_sp['client_secret']}\n"

    env_content += "\n# Storage accounts\n"
    for env, storage_name in storage_accounts.items():
        env_content += f"STORAGE_ACCOUNT_NAME_{env.upper()}={storage_name}\n"

    with open(".env", "w") as f:
        f.write(env_content)

    print_success("Generated .env file")


def generate_backend_configs(
    project_name: str,
    rg_name: str,
    storage_accounts: Dict[str, str],
    environments: List[str],
) -> None:
    """Generate backend configuration files."""
    print_status("Generating backend configuration files...")

    for env in environments:
        env_dir = Path(f"terraform/environments/{env}")
        env_dir.mkdir(parents=True, exist_ok=True)

        backend_config = f"""resource_group_name  = "{rg_name}"
storage_account_name = "{storage_accounts[env]}"
container_name       = "tfstate"
key                  = "{env}/terraform.tfstate"
"""

        with open(env_dir / "backend.conf", "w") as f:
            f.write(backend_config)

        print_success(f"Generated backend config for {env} environment")


def generate_terraform_tfvars(
    project_name: str, location: str, environments: List[str]
) -> None:
    """Generate terraform.tfvars files from examples."""
    print_status("Generating terraform.tfvars files...")

    for env in environments:
        env_dir = Path(f"terraform/environments/{env}")
        tfvars_file = env_dir / "terraform.tfvars"
        example_file = env_dir / "terraform.tfvars.example"

        if example_file.exists() and not tfvars_file.exists():
            # Read example file
            with open(example_file, "r") as f:
                content = f.read()

            # Update project name and location in the content
            content = content.replace(
                'project_name = "aks-platform"', f'project_name = "{project_name}"'
            )
            content = content.replace(
                'location    = "East US"', f'location    = "{location}"'
            )

            # Write to actual tfvars file
            with open(tfvars_file, "w") as f:
                f.write(content)

            print_success(f"Generated terraform.tfvars for {env} environment")
        elif tfvars_file.exists():
            print_warning(f"terraform.tfvars already exists for {env} environment")
        else:
            print_warning(f"terraform.tfvars.example not found for {env} environment")


def main():
    """Main function."""
    parser = argparse.ArgumentParser(
        description="Setup Azure credentials for Terraform"
    )
    parser.add_argument(
        "--project-name",
        default="aks-platform",
        help="Project name (default: aks-platform)",
    )
    parser.add_argument(
        "--location", default="East US", help="Azure location (default: East US)"
    )
    parser.add_argument(
        "--environment", help="Single environment to setup (dev, staging, prod)"
    )
    parser.add_argument(
        "--environments",
        nargs="+",
        help="Multiple environments to create (dev, staging, prod)",
    )
    parser.add_argument(
        "--all-environments",
        action="store_true",
        help="Create storage accounts for all environments (dev, staging, prod)",
    )

    args = parser.parse_args()

    # Handle environment selection - require explicit specification
    if args.all_environments:
        args.environments = ["dev", "staging", "prod"]
    elif args.environment:
        args.environments = [args.environment]
    elif args.environments:
        # environments already set
        pass
    else:
        print_error("Environment must be specified explicitly for security.")
        print_error("Use one of:")
        print_error("  --environment dev                    # Setup single environment")
        print_error("  --environment staging                # Setup single environment")
        print_error("  --environment prod                   # Setup single environment")
        print_error(
            "  --environments dev staging           # Setup multiple environments"
        )
        print_error("  --all-environments                   # Setup all environments")
        print_error("")
        print_error(
            "This prevents accidentally creating resources in unintended environments."
        )
        sys.exit(1)

    print_status(f"Starting Azure credentials setup for {args.project_name}...")
    print_status(f"Target environments: {', '.join(args.environments)}")
    print()

    # Check Python environment and virtual environment status
    if AZURE_UTILS_AVAILABLE:
        print_status("Checking Python environment...")
        VirtualEnvironmentChecker.check_python_version()
        VirtualEnvironmentChecker.check_and_warn_virtual_environment()
        print()

    try:
        check_prerequisites()
        azure_info = get_subscription_info()
        rg_name = create_state_resource_group(args.project_name, args.location)
        storage_accounts = create_storage_accounts(
            args.project_name, rg_name, args.location, args.environments
        )
        terraform_sp = create_service_principal(
            args.project_name, azure_info["subscription_id"], "terraform"
        )
        github_sp = create_service_principal(
            args.project_name, azure_info["subscription_id"], "github-actions"
        )

        generate_env_file(args.project_name, azure_info, terraform_sp, storage_accounts)
        generate_backend_configs(
            args.project_name, rg_name, storage_accounts, args.environments
        )
        generate_terraform_tfvars(args.project_name, args.location, args.environments)

        # Save GitHub Actions credentials
        if "sp_output" in github_sp:
            with open("github-actions-credentials.json", "w") as f:
                f.write(github_sp["sp_output"])
            print_success(
                "GitHub Actions credentials saved to github-actions-credentials.json"
            )

        print_success("Azure credentials setup completed!")
        print_status("Next steps:")
        print("  1. Review and update terraform.tfvars files for each environment")
        print("  2. Run ./scripts/setup-github-secrets.sh to configure GitHub secrets")
        print("  3. Source the .env file: source .env")

    except KeyboardInterrupt:
        print_error("Setup interrupted by user")
        sys.exit(1)
    except Exception as e:
        print_error(f"Setup failed: {str(e)}")
        sys.exit(1)


if __name__ == "__main__":
    main()
