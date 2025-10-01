#!/usr/bin/env python3
"""
Python Environment Checker for Azure AKS GitOps Platform

This utility checks the current Python environment and provides recommendations
for virtual environment setup and dependency management.

Usage:
    python3 scripts/check-python-env.py
    ./scripts/check-python-env.py

Features:
    - Detects if running in a virtual environment
    - Checks Python version compatibility
    - Validates required dependencies
    - Provides setup recommendations
    - Shows environment information
"""

import importlib.util
import os
import subprocess
import sys
from pathlib import Path
from typing import List, Optional, Tuple


def print_status(message: str) -> None:
    """Print status message with blue color."""
    print(f"\033[0;34m[INFO]\033[0m {message}")


def print_success(message: str) -> None:
    """Print success message with green color."""
    print(f"\033[0;32m[SUCCESS]\033[0m {message}")


def print_warning(message: str) -> None:
    """Print warning message with yellow color."""
    print(f"\033[1;33m[WARNING]\033[0m {message}")


def print_error(message: str) -> None:
    """Print error message with red color."""
    print(f"\033[0;31m[ERROR]\033[0m {message}")


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


def check_python_version() -> Tuple[bool, str]:
    """
    Check if Python version meets requirements.

    Returns:
        Tuple of (is_compatible, version_string)
    """
    version_info = sys.version_info
    version_string = f"{version_info.major}.{version_info.minor}.{version_info.micro}"

    # Require Python 3.7+
    is_compatible = version_info >= (3, 7)

    return is_compatible, version_string


def check_package_installed(package_name: str) -> Tuple[bool, Optional[str]]:
    """
    Check if a package is installed and get its version.

    Args:
        package_name: Name of the package to check (pip package name)

    Returns:
        Tuple of (is_installed, version)
    """
    # Map pip package names to their import names
    package_import_map = {
        "pyyaml": "yaml",
        "python-dateutil": "dateutil",
        "azure-cli": "azure.cli.core",
        "azure-cli-core": "azure.cli.core",
        "azure-identity": "azure.identity",
        "azure-mgmt-storage": "azure.mgmt.storage",
        "azure-mgmt-authorization": "azure.mgmt.authorization",
        "azure-mgmt-costmanagement": "azure.mgmt.costmanagement",
        "azure-mgmt-resource": "azure.mgmt.resource",
    }

    # Get the actual import name
    import_name = package_import_map.get(package_name, package_name)

    try:
        spec = importlib.util.find_spec(import_name)
        if spec is None:
            return False, None

        # Try to get version
        try:
            module = importlib.import_module(import_name)
            version = getattr(module, "__version__", "unknown")
            return True, version
        except ImportError:
            return False, None
    except (ImportError, AttributeError, ValueError):
        return False, None


def get_pip_version() -> Optional[str]:
    """Get pip version."""
    try:
        result = subprocess.run(
            [sys.executable, "-m", "pip", "--version"],
            capture_output=True,
            text=True,
            check=True,
        )
        # Extract version from output like "pip 23.3.1 from ..."
        version_line = result.stdout.strip()
        if version_line.startswith("pip "):
            return version_line.split()[1]
    except (subprocess.CalledProcessError, IndexError):
        pass
    return None


def check_requirements_file() -> Tuple[bool, List[str]]:
    """
    Check if requirements.txt exists and list packages.

    Returns:
        Tuple of (exists, package_list)
    """
    script_dir = Path(__file__).parent
    requirements_file = script_dir / "requirements.txt"

    if not requirements_file.exists():
        return False, []

    try:
        with open(requirements_file, "r") as f:
            lines = f.readlines()

        packages = []
        for line in lines:
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
                if package_name:
                    packages.append(package_name)

        return True, packages
    except IOError:
        return False, []


def find_virtual_environments() -> List[str]:
    """Find potential virtual environment directories."""
    project_root = Path(__file__).parent.parent
    venv_dirs = []

    # Common virtual environment directory names
    common_names = ["venv", ".venv", "env", ".env", "virtualenv"]

    for name in common_names:
        venv_path = project_root / name
        if venv_path.exists() and venv_path.is_dir():
            # Check if it looks like a virtual environment
            if (venv_path / "bin" / "activate").exists() or (
                venv_path / "Scripts" / "activate"
            ).exists():
                venv_dirs.append(str(venv_path))

    return venv_dirs


def main():
    """Main function to check Python environment."""
    print("Python Environment Checker for Azure AKS GitOps Platform")
    print("=" * 60)
    print()

    # Check Python version
    is_compatible, version = check_python_version()
    if is_compatible:
        print_success(f"Python version: {version} (compatible)")
    else:
        print_error(f"Python version: {version} (requires 3.7+)")
        print_status("Please upgrade Python to version 3.7 or higher")
        return 1

    # Check virtual environment
    is_venv, venv_path = is_virtual_environment()
    if is_venv:
        print_success(f"Virtual environment: Active ({venv_path})")
    else:
        print_warning("Virtual environment: Not active")

        # Look for existing virtual environments
        found_venvs = find_virtual_environments()
        if found_venvs:
            print_status("Found existing virtual environments:")
            for venv_dir in found_venvs:
                print(f"  - {venv_dir}")
            print_status("To activate, run: source <venv_path>/bin/activate")
        else:
            print_status("No virtual environments found")
            print_status("Create one with: ./scripts/setup-python-env.sh")

    # Check pip
    pip_version = get_pip_version()
    if pip_version:
        print_success(f"Pip version: {pip_version}")
    else:
        print_warning("Pip: Not available or not working")

    print()

    # Check requirements file and dependencies
    req_exists, packages = check_requirements_file()
    if req_exists:
        print_success(f"Requirements file: Found ({len(packages)} packages)")

        if is_venv:
            print_status("Checking installed packages...")
            missing_packages = []
            installed_packages = []

            for package in packages[:10]:  # Check first 10 to avoid spam
                is_installed, version = check_package_installed(package)
                if is_installed:
                    installed_packages.append(f"{package} ({version})")
                else:
                    missing_packages.append(package)

            if installed_packages:
                print_success(f"Installed packages ({len(installed_packages)}):")
                for pkg in installed_packages[:5]:  # Show first 5
                    print(f"  OK {pkg}")
                if len(installed_packages) > 5:
                    print(f"  ... and {len(installed_packages) - 5} more")

            if missing_packages:
                print_warning(f"Missing packages ({len(missing_packages)}):")
                for pkg in missing_packages[:5]:  # Show first 5
                    print(f"  ERROR {pkg}")
                if len(missing_packages) > 5:
                    print(f"  ... and {len(missing_packages) - 5} more")
                print_status("Install with: pip install -r scripts/requirements.txt")
        else:
            print_status("Activate virtual environment to check installed packages")
    else:
        print_error("Requirements file: Not found (scripts/requirements.txt)")

    print()

    # Provide recommendations
    print_status("Recommendations:")

    if not is_venv:
        print("  1. Create and activate a virtual environment:")
        print("     ./scripts/setup-python-env.sh")
        print("     source venv/bin/activate")

    if req_exists and is_venv:
        print("  2. Install/update dependencies:")
        print("     pip install -r scripts/requirements.txt")

    if is_venv:
        print("  3. For development work, install dev dependencies:")
        print("     pip install -r scripts/requirements-dev.txt")

    print("  4. Use the Makefile for common tasks:")
    print("     make help")

    print()

    # Environment summary
    print_status("Environment Summary:")
    print(f"  Python: {version} ({'OK' if is_compatible else 'ERROR'})")
    print(f"  Virtual Environment: {'OK' if is_venv else 'ERROR'}")
    print(f"  Pip: {'OK' if pip_version else 'ERROR'}")
    print(f"  Requirements: {'OK' if req_exists else 'ERROR'}")

    if is_venv and req_exists:
        print_success("Environment is ready for development!")
    elif not is_venv:
        print_warning("Set up virtual environment for best practices")

    return 0


if __name__ == "__main__":
    sys.exit(main())
