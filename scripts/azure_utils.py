#!/usr/bin/env python3

"""
Azure Utilities Module

Shared utilities for Azure AKS GitOps Platform Python scripts.
This module provides common functionality used across multiple scripts
to reduce code duplication and ensure consistency.

Key Features:
1. Azure authentication and credential management
2. Common Azure CLI operations
3. Consistent error handling and logging
4. Configuration management
5. Cross-platform compatibility utilities

Usage:
    from azure_utils import AzureHelper, print_status, print_error

    helper = AzureHelper()
    subscription_id = helper.get_subscription_id()
"""

import json
import os
import subprocess
import sys
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional, Tuple


class Colors:
    """ANSI color codes for consistent terminal output."""

    RED = "\033[0;31m"
    GREEN = "\033[0;32m"
    YELLOW = "\033[1;33m"
    BLUE = "\033[0;34m"
    NC = "\033[0m"  # No Color


def print_status(message: str) -> None:
    """Print informational message with blue color."""
    print(f"{Colors.BLUE}[INFO]{Colors.NC} {message}")


def print_success(message: str) -> None:
    """Print success message with green color."""
    print(f"{Colors.GREEN}[SUCCESS]{Colors.NC} {message}")


def print_warning(message: str) -> None:
    """Print warning message with yellow color."""
    print(f"{Colors.YELLOW}[WARNING]{Colors.NC} {message}")


def print_error(message: str) -> None:
    """Print error message with red color."""
    print(f"{Colors.RED}[ERROR]{Colors.NC} {message}")


class VirtualEnvironmentChecker:
    """Utility class for checking and managing Python virtual environments."""

    @staticmethod
    def is_virtual_environment() -> Tuple[bool, Optional[str]]:
        """
        Check if running in a virtual environment.

        Returns:
            Tuple of (is_venv, venv_path)
        """
        # Check for virtual environment indicators
        if hasattr(sys, "real_prefix"):
            # virtualenv
            return True, getattr(sys, "real_prefix", None)

        if hasattr(sys, "base_prefix") and sys.base_prefix != sys.prefix:
            # venv
            return True, sys.prefix

        # Check environment variables
        if os.environ.get("VIRTUAL_ENV"):
            return True, os.environ.get("VIRTUAL_ENV")

        return False, None

    @staticmethod
    def find_virtual_environments(project_root: Optional[str] = None) -> List[str]:
        """
        Find potential virtual environment directories in the project.

        Args:
            project_root: Root directory to search (defaults to current script's parent)

        Returns:
            List of virtual environment directory paths
        """
        if project_root is None:
            # Default to the parent directory of the scripts folder
            script_dir = Path(__file__).parent
            project_root = script_dir.parent
        else:
            project_root = Path(project_root)

        venv_dirs = []

        # Common virtual environment directory names
        common_names = ["venv", ".venv", "env", ".env", "virtualenv"]

        for name in common_names:
            venv_path = project_root / name
            if venv_path.exists() and venv_path.is_dir():
                # Check if it looks like a virtual environment
                activate_script = venv_path / "bin" / "activate"
                activate_script_win = venv_path / "Scripts" / "activate"

                if activate_script.exists() or activate_script_win.exists():
                    venv_dirs.append(str(venv_path))

        return venv_dirs

    @staticmethod
    def check_and_warn_virtual_environment() -> bool:
        """
        Check virtual environment status and provide warnings/recommendations.

        Returns:
            True if running in virtual environment, False otherwise
        """
        is_venv, venv_path = VirtualEnvironmentChecker.is_virtual_environment()

        if is_venv:
            print_success(f"Running in virtual environment: {venv_path}")
            return True
        else:
            print_warning("Not running in a virtual environment")
            print_status("Virtual environments are recommended for Python development")

            # Look for existing virtual environments
            found_venvs = VirtualEnvironmentChecker.find_virtual_environments()
            if found_venvs:
                print_status("Found existing virtual environments:")
                for venv_dir in found_venvs:
                    print(f"  - {venv_dir}")
                print_status("To activate, run:")
                print(f"  source {found_venvs[0]}/bin/activate")
                print("  # OR use the helper script:")
                print("  source ./activate-python-env.sh")
            else:
                print_status("No virtual environments found")
                print_status("Create one with:")
                print("  ./scripts/setup-python-env.sh")
                print("  # OR manually:")
                print("  python3 -m venv venv && source venv/bin/activate")

            print()
            return False

    @staticmethod
    def get_python_version_info() -> Dict[str, str]:
        """
        Get Python version information.

        Returns:
            Dictionary with version information
        """
        version_info = sys.version_info
        return {
            "version": f"{version_info.major}.{version_info.minor}.{version_info.micro}",
            "major": str(version_info.major),
            "minor": str(version_info.minor),
            "micro": str(version_info.micro),
            "is_compatible": version_info >= (3, 7),
            "executable": sys.executable,
            "prefix": sys.prefix,
            "base_prefix": getattr(sys, "base_prefix", sys.prefix),
        }

    @staticmethod
    def check_python_version() -> bool:
        """
        Check if Python version meets requirements.

        Returns:
            True if compatible, False otherwise
        """
        version_info = VirtualEnvironmentChecker.get_python_version_info()

        if version_info["is_compatible"]:
            print_success(f"Python version: {version_info['version']} (compatible)")
            return True
        else:
            print_error(f"Python version: {version_info['version']} (requires 3.7+)")
            print_status("Please upgrade Python to version 3.7 or higher")
            return False


class AzureHelper:
    """Helper class for common Azure operations."""

    def __init__(self, subscription_id: Optional[str] = None):
        """Initialize Azure helper with optional subscription ID."""
        self.subscription_id = subscription_id or self.get_subscription_id()

    def get_subscription_id(self) -> str:
        """Get current Azure subscription ID."""
        try:
            result = subprocess.run(
                ["az", "account", "show", "--query", "id", "-o", "tsv"],
                capture_output=True,
                text=True,
                check=True,
            )
            return result.stdout.strip()
        except subprocess.CalledProcessError as e:
            print_error(f"Failed to get subscription ID: {e}")
            print_status("Please run 'az login' first")
            sys.exit(1)
        except FileNotFoundError:
            print_error("Azure CLI not found")
            print_status(
                "Please install Azure CLI: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
            )
            sys.exit(1)

    def get_subscription_info(self) -> Dict:
        """Get detailed subscription information."""
        try:
            result = subprocess.run(
                ["az", "account", "show"], capture_output=True, text=True, check=True
            )
            return json.loads(result.stdout)
        except subprocess.CalledProcessError as e:
            print_error(f"Failed to get subscription info: {e}")
            return {}
        except json.JSONDecodeError as e:
            print_error(f"Failed to parse subscription info: {e}")
            return {}

    def check_azure_cli_auth(self) -> bool:
        """Check if Azure CLI is authenticated."""
        try:
            subprocess.run(
                ["az", "account", "show"], capture_output=True, text=True, check=True
            )
            return True
        except subprocess.CalledProcessError:
            return False
        except FileNotFoundError:
            print_error("Azure CLI not found")
            return False

    def get_resource_groups(self, name_filter: Optional[str] = None) -> List[str]:
        """Get list of resource groups, optionally filtered by name."""
        try:
            cmd = ["az", "group", "list", "--query", "[].name", "-o", "tsv"]
            result = subprocess.run(cmd, capture_output=True, text=True, check=True)

            resource_groups = [
                rg.strip() for rg in result.stdout.split("\n") if rg.strip()
            ]

            if name_filter:
                resource_groups = [rg for rg in resource_groups if name_filter in rg]

            return resource_groups
        except subprocess.CalledProcessError as e:
            print_warning(f"Failed to list resource groups: {e}")
            return []

    def resource_group_exists(self, name: str) -> bool:
        """Check if a resource group exists."""
        try:
            result = subprocess.run(
                ["az", "group", "show", "--name", name], capture_output=True, text=True
            )
            return result.returncode == 0
        except Exception:
            return False

    def get_locations(self) -> List[str]:
        """Get list of available Azure locations."""
        try:
            result = subprocess.run(
                ["az", "account", "list-locations", "--query", "[].name", "-o", "tsv"],
                capture_output=True,
                text=True,
                check=True,
            )
            return [loc.strip() for loc in result.stdout.split("\n") if loc.strip()]
        except subprocess.CalledProcessError as e:
            print_warning(f"Failed to list locations: {e}")
            return [
                "eastus",
                "westus",
                "westus2",
                "centralus",
                "eastus2",
                "southcentralus",
            ]  # US regions fallback


class ConfigManager:
    """Configuration management for Azure scripts."""

    def __init__(self, config_file: Optional[str] = None):
        """Initialize configuration manager."""
        self.config_file = config_file or os.path.expanduser(
            "~/.azure-platform-config.json"
        )
        self.config = self.load_config()

    def load_config(self) -> Dict:
        """Load configuration from file."""
        if os.path.exists(self.config_file):
            try:
                with open(self.config_file, "r") as f:
                    return json.load(f)
            except (json.JSONDecodeError, IOError) as e:
                print_warning(f"Failed to load config: {e}")

        return self.get_default_config()

    def save_config(self) -> None:
        """Save configuration to file."""
        try:
            os.makedirs(os.path.dirname(self.config_file), exist_ok=True)
            with open(self.config_file, "w") as f:
                json.dump(self.config, f, indent=2)
        except IOError as e:
            print_warning(f"Failed to save config: {e}")

    def get_default_config(self) -> Dict:
        """Get default configuration."""
        return {
            "project_name": "aks-platform",
            "default_location": "eastus",  # US East region
            "default_environment": "dev",
            "created_at": datetime.now().isoformat(),
            "version": "1.0",
        }

    def get(self, key: str, default=None):
        """Get configuration value."""
        return self.config.get(key, default)

    def set(self, key: str, value) -> None:
        """Set configuration value."""
        self.config[key] = value
        self.save_config()


class DependencyChecker:
    """Check and manage script dependencies."""

    @staticmethod
    def check_python_version(min_version: Tuple[int, int] = (3, 7)) -> bool:
        """Check if Python version meets minimum requirements."""
        current = sys.version_info[:2]
        if current < min_version:
            print_error(
                f"Python {min_version[0]}.{min_version[1]}+ required (found: {current[0]}.{current[1]})"
            )
            return False
        return True

    @staticmethod
    def check_command(command: str) -> bool:
        """Check if a command is available in PATH."""
        try:
            subprocess.run(
                [command, "--version"], capture_output=True, text=True, check=True
            )
            return True
        except (subprocess.CalledProcessError, FileNotFoundError):
            return False

    @staticmethod
    def check_python_package(package: str) -> bool:
        """Check if a Python package is installed."""
        try:
            __import__(package)
            return True
        except ImportError:
            return False

    @staticmethod
    def install_python_package(package: str) -> bool:
        """Install a Python package using pip."""
        # Check if in virtual environment first
        is_venv, _ = VirtualEnvironmentChecker.is_virtual_environment()

        if not is_venv:
            print_warning(f"Installing {package} outside virtual environment")
            print_status(
                "Consider using a virtual environment for better dependency management"
            )

        try:
            subprocess.run(
                [sys.executable, "-m", "pip", "install", package],
                capture_output=True,
                text=True,
                check=True,
            )
            return True
        except subprocess.CalledProcessError as e:
            print_error(f"Failed to install {package}: {e}")
            return False

    @staticmethod
    def check_requirements_file(
        requirements_path: Optional[str] = None,
    ) -> Tuple[bool, List[str]]:
        """
        Check if requirements file exists and list missing packages.

        Args:
            requirements_path: Path to requirements file (defaults to scripts/requirements.txt)

        Returns:
            Tuple of (file_exists, missing_packages)
        """
        if requirements_path is None:
            script_dir = Path(__file__).parent
            requirements_path = script_dir / "requirements.txt"
        else:
            requirements_path = Path(requirements_path)

        if not requirements_path.exists():
            return False, []

        missing_packages = []

        try:
            with open(requirements_path, "r") as f:
                for line in f:
                    line = line.strip()
                    if line and not line.startswith("#"):
                        # Extract package name (before == or >= etc.)
                        package_name = (
                            line.split("==")[0]
                            .split(">=")[0]
                            .split("<=")[0]
                            .split("~=")[0]
                            .strip()
                        )
                        if package_name and not DependencyChecker.check_python_package(
                            package_name
                        ):
                            missing_packages.append(package_name)
        except IOError:
            return False, []

        return True, missing_packages

    @staticmethod
    def install_requirements(
        requirements_path: Optional[str] = None, use_venv: bool = True
    ) -> bool:
        """
        Install packages from requirements file.

        Args:
            requirements_path: Path to requirements file
            use_venv: Whether to check for virtual environment

        Returns:
            True if successful, False otherwise
        """
        if requirements_path is None:
            script_dir = Path(__file__).parent
            requirements_path = script_dir / "requirements.txt"
        else:
            requirements_path = Path(requirements_path)

        if not requirements_path.exists():
            print_error(f"Requirements file not found: {requirements_path}")
            return False

        if use_venv:
            is_venv, _ = VirtualEnvironmentChecker.is_virtual_environment()
            if not is_venv:
                print_warning("Installing packages outside virtual environment")
                print_status("Consider activating a virtual environment first")

        try:
            print_status(f"Installing packages from {requirements_path}")
            subprocess.run(
                [sys.executable, "-m", "pip", "install", "-r", str(requirements_path)],
                capture_output=True,
                text=True,
                check=True,
            )
            print_success("Packages installed successfully")
            return True
        except subprocess.CalledProcessError as e:
            print_error(f"Failed to install packages: {e}")
            return False

    def check_azure_dependencies(self) -> bool:
        """Check Azure-specific dependencies."""
        dependencies = {
            "Azure CLI": lambda: self.check_command("az"),
            "Azure Identity": lambda: self.check_python_package("azure.identity"),
            "Azure Management": lambda: self.check_python_package(
                "azure.mgmt.resource"
            ),
        }

        missing = []
        for name, check_func in dependencies.items():
            if not check_func():
                missing.append(name)

        if missing:
            print_error(f"Missing dependencies: {', '.join(missing)}")
            return False

        return True


def format_json_output(data: Dict, indent: int = 2) -> str:
    """Format dictionary as pretty JSON string."""
    return json.dumps(data, indent=indent, default=str)


def safe_run_command(
    command: List[str], capture_output: bool = True
) -> Tuple[bool, str, str]:
    """Safely run a command and return success status, stdout, stderr."""
    try:
        result = subprocess.run(
            command, capture_output=capture_output, text=True, check=False
        )
        return result.returncode == 0, result.stdout, result.stderr
    except FileNotFoundError:
        return False, "", f"Command not found: {command[0]}"
    except Exception as e:
        return False, "", str(e)


def get_script_directory() -> str:
    """Get the directory containing the current script."""
    return os.path.dirname(os.path.abspath(__file__))


def get_project_root() -> str:
    """Get the project root directory (parent of scripts directory)."""
    return os.path.dirname(get_script_directory())


# Example usage and testing
if __name__ == "__main__":
    print_status("Testing Azure Utilities Module")

    # Test dependency checker
    checker = DependencyChecker()
    print(f"Python version OK: {checker.check_python_version()}")
    print(f"Azure CLI available: {checker.check_command('az')}")

    # Test Azure helper
    try:
        helper = AzureHelper()
        print(f"Subscription ID: {helper.subscription_id}")
        print(f"Authenticated: {helper.check_azure_cli_auth()}")
    except SystemExit:
        print("Azure CLI not authenticated")

    # Test config manager
    config = ConfigManager()
    print(f"Default project name: {config.get('project_name')}")

    print_success("Azure utilities module test completed")
