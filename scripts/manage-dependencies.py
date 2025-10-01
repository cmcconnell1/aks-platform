#!/usr/bin/env python3
"""
Dependency Management Script for Azure AKS GitOps Platform

This script helps manage Python dependencies across different requirement files,
check for updates, security vulnerabilities, and maintain dependency hygiene.

Usage:
    python3 scripts/manage-dependencies.py [command] [options]

Commands:
    check       Check current dependencies and their status
    update      Update dependencies to latest compatible versions
    audit       Run security audit on dependencies
    freeze      Generate frozen requirements from current environment
    sync        Synchronize dependencies across requirement files
    outdated    Show outdated packages
    help        Show this help message

Examples:
    python3 scripts/manage-dependencies.py check
    python3 scripts/manage-dependencies.py update --dry-run
    python3 scripts/manage-dependencies.py audit
    python3 scripts/manage-dependencies.py freeze --output requirements-frozen.txt
"""

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path
from typing import Dict, List, Optional, Tuple


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


class DependencyManager:
    """Manages Python dependencies for the project."""

    def __init__(self):
        self.script_dir = Path(__file__).parent
        self.project_root = self.script_dir.parent
        self.requirements_files = {
            "main": self.script_dir / "requirements.txt",
            "dev": self.script_dir / "requirements-dev.txt",
            "test": self.script_dir / "requirements-test.txt",
        }

    def run_command(
        self, cmd: List[str], capture_output: bool = True
    ) -> subprocess.CompletedProcess:
        """Run a command and return the result."""
        try:
            return subprocess.run(
                cmd, capture_output=capture_output, text=True, check=True
            )
        except subprocess.CalledProcessError as e:
            print_error(f"Command failed: {' '.join(cmd)}")
            if e.stdout:
                print(f"STDOUT: {e.stdout}")
            if e.stderr:
                print(f"STDERR: {e.stderr}")
            raise

    def check_virtual_environment(self) -> bool:
        """Check if running in a virtual environment."""
        return hasattr(sys, "real_prefix") or (
            hasattr(sys, "base_prefix") and sys.base_prefix != sys.prefix
        )

    def parse_requirements_file(self, file_path: Path) -> List[Dict[str, str]]:
        """Parse a requirements file and return package information."""
        if not file_path.exists():
            return []

        packages = []
        with open(file_path, "r") as f:
            for line_num, line in enumerate(f, 1):
                line = line.strip()
                if line and not line.startswith("#"):
                    # Parse package specification
                    match = re.match(r"^([a-zA-Z0-9_-]+)([><=!~]+)([0-9.]+.*)?", line)
                    if match:
                        name, operator, version = match.groups()
                        packages.append(
                            {
                                "name": name,
                                "operator": operator,
                                "version": version or "",
                                "line": line,
                                "line_number": line_num,
                            }
                        )
                    else:
                        print_warning(
                            f"Could not parse line {line_num} in {file_path.name}: {line}"
                        )

        return packages

    def get_installed_packages(self) -> Dict[str, str]:
        """Get currently installed packages and their versions."""
        try:
            result = self.run_command(
                [sys.executable, "-m", "pip", "list", "--format=json"]
            )
            packages = json.loads(result.stdout)
            return {pkg["name"].lower(): pkg["version"] for pkg in packages}
        except (subprocess.CalledProcessError, json.JSONDecodeError):
            print_error("Failed to get installed packages")
            return {}

    def get_outdated_packages(self) -> List[Dict[str, str]]:
        """Get list of outdated packages."""
        try:
            result = self.run_command(
                [sys.executable, "-m", "pip", "list", "--outdated", "--format=json"]
            )
            return json.loads(result.stdout)
        except (subprocess.CalledProcessError, json.JSONDecodeError):
            print_error("Failed to get outdated packages")
            return []

    def check_dependencies(self) -> None:
        """Check current dependencies and their status."""
        print_status("Checking dependencies...")

        if not self.check_virtual_environment():
            print_warning("Not running in a virtual environment")
            print_status(
                "Activate virtual environment for accurate dependency checking"
            )
            return

        installed_packages = self.get_installed_packages()
        print_success(f"Found {len(installed_packages)} installed packages")

        for req_type, req_file in self.requirements_files.items():
            if not req_file.exists():
                print_warning(
                    f"{req_type.title()} requirements file not found: {req_file.name}"
                )
                continue

            packages = self.parse_requirements_file(req_file)
            print_status(
                f"{req_type.title()} requirements ({req_file.name}): {len(packages)} packages"
            )

            missing_packages = []
            for pkg in packages:
                pkg_name = pkg["name"].lower()
                if pkg_name not in installed_packages:
                    missing_packages.append(pkg["name"])

            if missing_packages:
                print_warning(
                    f"Missing packages in {req_type}: {', '.join(missing_packages)}"
                )
            else:
                print_success(f"All {req_type} packages are installed")

    def audit_security(self) -> None:
        """Run security audit on dependencies."""
        print_status("Running security audit...")

        if not self.check_virtual_environment():
            print_error("Virtual environment required for security audit")
            return

        # Try pip-audit first
        try:
            print_status("Running pip-audit...")
            result = self.run_command(
                [sys.executable, "-m", "pip-audit", "--format=json"]
            )
            audit_results = json.loads(result.stdout)

            if audit_results:
                print_error(f"Found {len(audit_results)} security vulnerabilities")
                for vuln in audit_results[:5]:  # Show first 5
                    print(
                        f"  - {vuln.get('package', 'unknown')}: {vuln.get('vulnerability_id', 'unknown')}"
                    )
            else:
                print_success("No security vulnerabilities found")

        except subprocess.CalledProcessError:
            print_warning("pip-audit not available, trying safety...")

            # Fallback to safety
            try:
                result = self.run_command(
                    [sys.executable, "-m", "safety", "check", "--json"]
                )
                safety_results = json.loads(result.stdout)

                if safety_results:
                    print_error(f"Found {len(safety_results)} security issues")
                    for issue in safety_results[:5]:  # Show first 5
                        print(
                            f"  - {issue.get('package', 'unknown')}: {issue.get('vulnerability', 'unknown')}"
                        )
                else:
                    print_success("No security issues found")

            except subprocess.CalledProcessError:
                print_warning("Neither pip-audit nor safety available")
                print_status("Install with: pip install pip-audit safety")

    def show_outdated(self) -> None:
        """Show outdated packages."""
        print_status("Checking for outdated packages...")

        if not self.check_virtual_environment():
            print_error("Virtual environment required to check outdated packages")
            return

        outdated = self.get_outdated_packages()

        if outdated:
            print_warning(f"Found {len(outdated)} outdated packages:")
            for pkg in outdated:
                print(f"  {pkg['name']}: {pkg['version']} -> {pkg['latest_version']}")
        else:
            print_success("All packages are up to date")

    def freeze_requirements(self, output_file: Optional[str] = None) -> None:
        """Generate frozen requirements from current environment."""
        print_status("Generating frozen requirements...")

        if not self.check_virtual_environment():
            print_error("Virtual environment required to freeze requirements")
            return

        try:
            result = self.run_command([sys.executable, "-m", "pip", "freeze"])
            frozen_requirements = result.stdout

            if output_file:
                output_path = Path(output_file)
            else:
                output_path = self.script_dir / "requirements-frozen.txt"

            with open(output_path, "w") as f:
                f.write("# Frozen requirements generated by manage-dependencies.py\n")
                f.write(
                    "# This file contains exact versions of all installed packages\n"
                )
                f.write("# Install with: pip install -r requirements-frozen.txt\n\n")
                f.write(frozen_requirements)

            print_success(f"Frozen requirements saved to: {output_path}")

        except subprocess.CalledProcessError:
            print_error("Failed to freeze requirements")

    def update_dependencies(self, dry_run: bool = False) -> None:
        """Update dependencies to latest compatible versions."""
        print_status("Updating dependencies...")

        if not self.check_virtual_environment():
            print_error("Virtual environment required to update dependencies")
            return

        if dry_run:
            print_status("Dry run mode - showing what would be updated")
            self.show_outdated()
            return

        # Update pip first
        try:
            print_status("Updating pip...")
            self.run_command(
                [sys.executable, "-m", "pip", "install", "--upgrade", "pip"]
            )
            print_success("Pip updated")
        except subprocess.CalledProcessError:
            print_warning("Failed to update pip")

        # Update packages from requirements files
        for req_type, req_file in self.requirements_files.items():
            if req_file.exists():
                print_status(f"Updating {req_type} dependencies...")
                try:
                    self.run_command(
                        [
                            sys.executable,
                            "-m",
                            "pip",
                            "install",
                            "--upgrade",
                            "-r",
                            str(req_file),
                        ]
                    )
                    print_success(f"{req_type.title()} dependencies updated")
                except subprocess.CalledProcessError:
                    print_error(f"Failed to update {req_type} dependencies")


def main():
    """Main function."""
    parser = argparse.ArgumentParser(
        description="Dependency Management Script for Azure AKS GitOps Platform",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )

    parser.add_argument(
        "command",
        nargs="?",
        default="check",
        choices=["check", "update", "audit", "freeze", "outdated", "help"],
        help="Command to execute",
    )

    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Show what would be done without making changes",
    )

    parser.add_argument(
        "--output", "-o", type=str, help="Output file for freeze command"
    )

    args = parser.parse_args()

    if args.command == "help":
        parser.print_help()
        return 0

    manager = DependencyManager()

    try:
        if args.command == "check":
            manager.check_dependencies()
        elif args.command == "update":
            manager.update_dependencies(dry_run=args.dry_run)
        elif args.command == "audit":
            manager.audit_security()
        elif args.command == "freeze":
            manager.freeze_requirements(args.output)
        elif args.command == "outdated":
            manager.show_outdated()

        return 0

    except Exception as e:
        print_error(f"Command failed: {e}")
        return 1


if __name__ == "__main__":
    sys.exit(main())
