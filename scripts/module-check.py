#!/usr/bin/env python3

"""
Module Dependency Checker for Azure AKS GitOps Platform Scripts

This script analyzes Python scripts to identify their module dependencies,
helping ensure all required packages are available before execution.

Usage:
    python3 scripts/module-check.py [script_path]
    python3 scripts/module-check.py  # Defaults to setup-azure-credentials.py

    Analyze specific script:
    python3 scripts/module-check.py ./scripts/dynamic-cost-estimator.py
"""

import ast
import os
import re
import sys
from modulefinder import ModuleFinder
from pathlib import Path

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

    # Fallback color functions
    def print_status(msg):
        print(f"[INFO] {msg}")

    def print_success(msg):
        print(f"[SUCCESS] {msg}")

    def print_warning(msg):
        print(f"[WARNING] {msg}")

    def print_error(msg):
        print(f"[ERROR] {msg}")


def analyze_imports_manually(script_path):
    """
    Manually analyze imports when ModuleFinder fails.

    Args:
        script_path (str): Path to the Python script to analyze

    Returns:
        tuple: (found_imports, missing_modules, script_info)
    """
    try:
        with open(script_path, "r", encoding="utf-8") as f:
            content = f.read()

        # Parse the AST to find imports
        tree = ast.parse(content)

        imports = set()
        for node in ast.walk(tree):
            if isinstance(node, ast.Import):
                for alias in node.names:
                    imports.add(alias.name)
            elif isinstance(node, ast.ImportFrom):
                if node.module:
                    imports.add(node.module)

        # Try to import each module to see if it's available
        available_modules = {}
        missing_modules = {}

        for module_name in imports:
            try:
                imported_module = __import__(module_name)

                # Create a mock module object for compatibility
                class MockModule:
                    def __init__(self, name, real_module):
                        self.name = name
                        self.globalnames = {}
                        # Try to get the real file path
                        if hasattr(real_module, "__file__") and real_module.__file__:
                            self.__file__ = real_module.__file__
                        else:
                            self.__file__ = f"<module '{name}'>"

                available_modules[module_name] = MockModule(
                    module_name, imported_module
                )
            except ImportError:
                missing_modules[module_name] = ["Import failed"]

        script_info = {
            "path": script_path,
            "size": os.path.getsize(script_path),
            "exists": True,
        }

        print("Note: Using manual import analysis due to ModuleFinder issues")
        return available_modules, missing_modules, script_info

    except Exception as e:
        print(f"Manual analysis also failed: {e}")
        return None, None, None


def analyze_script_dependencies(script_path):
    """
    Analyze a Python script to find its module dependencies.

    Args:
        script_path (str): Path to the Python script to analyze

    Returns:
        tuple: (loaded_modules, missing_modules, script_info)
    """
    if not os.path.exists(script_path):
        print(f"Error: Script not found: {script_path}")
        return None, None, None

    print(f"Analyzing dependencies for: {script_path}")
    print("=" * 60)

    try:
        finder = ModuleFinder()

        # Check if the file is actually a Python script
        with open(script_path, "r", encoding="utf-8") as f:
            first_line = f.readline().strip()
            if not (
                first_line.startswith("#!") and "python" in first_line
            ) and not script_path.endswith(".py"):
                print(f"Warning: {script_path} may not be a Python script")

        finder.run_script(script_path)

        # Get script info
        script_info = {
            "path": script_path,
            "size": os.path.getsize(script_path),
            "exists": True,
        }

        return finder.modules, finder.badmodules, script_info

    except SyntaxError as e:
        print(f"Syntax error in script: {e}")
        print(
            "This may not be a valid Python script or may have Python version compatibility issues."
        )
        return None, None, None
    except AttributeError as e:
        if "'NoneType' object has no attribute 'is_package'" in str(e):
            print("ModuleFinder encountered an issue with module resolution.")
            print(
                "This often happens with complex import patterns or missing dependencies."
            )
            print("Trying alternative analysis...")
            return analyze_imports_manually(script_path)
        else:
            print(f"Attribute error analyzing script: {e}")
            return None, None, None
    except Exception as e:
        print(f"Error analyzing script: {e}")
        print(f"Error type: {type(e).__name__}")
        return None, None, None


def print_loaded_modules(modules):
    """Print information about successfully loaded modules."""
    print("\nSuccessfully Loaded Modules:")
    print("-" * 40)

    # Separate standard library from third-party modules
    stdlib_modules = []
    thirdparty_modules = []
    local_modules = []

    # Known third-party packages
    known_thirdparty = {
        "requests",
        "numpy",
        "pandas",
        "flask",
        "django",
        "boto3",
        "azure",
        "google",
        "aws",
        "click",
        "pyyaml",
        "jinja2",
        "sqlalchemy",
        "pytest",
        "matplotlib",
        "scipy",
        "sklearn",
        "tensorflow",
        "torch",
        "fastapi",
    }

    for name, mod in modules.items():
        root_name = name.split(".")[0]

        if hasattr(mod, "__file__") and mod.__file__:
            if "site-packages" in mod.__file__ or root_name in known_thirdparty:
                thirdparty_modules.append((name, mod))
            elif name.startswith(".") or "scripts" in mod.__file__:
                local_modules.append((name, mod))
            else:
                stdlib_modules.append((name, mod))
        else:
            # Check if it's a known third-party package
            if root_name in known_thirdparty:
                thirdparty_modules.append((name, mod))
            else:
                stdlib_modules.append((name, mod))

    # Print categorized modules
    if stdlib_modules:
        print("\nStandard Library Modules:")
        for name, mod in sorted(stdlib_modules):
            globals_preview = (
                list(mod.globalnames.keys())[:3] if mod.globalnames else []
            )
            globals_str = ", ".join(globals_preview)
            if len(mod.globalnames) > 3:
                globals_str += f" ... (+{len(mod.globalnames) - 3} more)"
            print(f"  {name}: {globals_str}")

    if thirdparty_modules:
        print("\nThird-party Modules:")
        for name, mod in sorted(thirdparty_modules):
            globals_preview = (
                list(mod.globalnames.keys())[:3] if mod.globalnames else []
            )
            globals_str = ", ".join(globals_preview)
            if len(mod.globalnames) > 3:
                globals_str += f" ... (+{len(mod.globalnames) - 3} more)"
            print(f"  {name}: {globals_str}")

    if local_modules:
        print("\nLocal Modules:")
        for name, mod in sorted(local_modules):
            globals_preview = (
                list(mod.globalnames.keys())[:3] if mod.globalnames else []
            )
            globals_str = ", ".join(globals_preview)
            if len(mod.globalnames) > 3:
                globals_str += f" ... (+{len(mod.globalnames) - 3} more)"
            print(f"  {name}: {globals_str}")


def print_missing_modules(badmodules):
    """Print information about modules that could not be imported."""
    if not badmodules:
        print("\nAll modules imported successfully!")
        return

    print(f"\nModules Not Imported ({len(badmodules)} total):")
    print("-" * 40)

    # Categorize missing modules
    likely_thirdparty = []
    likely_optional = []
    likely_system = []

    for module_name in sorted(badmodules.keys()):
        if any(
            pkg in module_name.lower() for pkg in ["azure", "boto", "google", "aws"]
        ):
            likely_thirdparty.append(module_name)
        elif any(pkg in module_name.lower() for pkg in ["win", "posix", "_", "nt"]):
            likely_system.append(module_name)
        else:
            likely_optional.append(module_name)

    if likely_thirdparty:
        print("\nLikely Third-party Dependencies:")
        for module in likely_thirdparty:
            print(f"  - {module}")
        print("  Install with: pip install <package-name>")

    if likely_optional:
        print("\nPossibly Optional Dependencies:")
        for module in likely_optional:
            print(f"  - {module}")

    if likely_system:
        print("\nSystem/Platform Specific:")
        for module in likely_system:
            print(f"  - {module}")


def generate_requirements(modules, badmodules):
    """Generate a requirements.txt suggestion based on found modules."""
    print("\nSuggested requirements.txt entries:")
    print("-" * 40)

    # Common package mappings
    package_mappings = {
        "azure": "azure-cli",
        "azure.identity": "azure-identity",
        "azure.mgmt": "azure-mgmt",
        "requests": "requests",
        "boto3": "boto3",
        "google": "google-cloud",
        "yaml": "PyYAML",
        "jwt": "PyJWT",
        "dateutil": "python-dateutil",
    }

    suggested_packages = set()

    # Check loaded third-party modules
    for name, mod in modules.items():
        if (
            hasattr(mod, "__file__")
            and mod.__file__
            and "site-packages" in mod.__file__
        ):
            root_package = name.split(".")[0]
            if root_package in package_mappings:
                suggested_packages.add(package_mappings[root_package])
            elif not root_package.startswith("_"):
                suggested_packages.add(root_package)

    # Check missing modules that might be installable
    for module_name in badmodules.keys():
        root_package = module_name.split(".")[0]
        if root_package in package_mappings:
            suggested_packages.add(package_mappings[root_package])
        elif any(
            pkg in root_package.lower()
            for pkg in ["azure", "requests", "boto", "google"]
        ):
            suggested_packages.add(root_package)

    if suggested_packages:
        for package in sorted(suggested_packages):
            print(f"  {package}")
    else:
        print("  No additional packages required (uses only standard library)")


def main():
    """Main function to run the module dependency analysis."""
    print("Module Dependency Checker for Azure AKS GitOps Platform")
    print("=" * 60)
    print()

    # Check Python environment
    if AZURE_UTILS_AVAILABLE:
        print_status("Checking Python environment...")
        VirtualEnvironmentChecker.check_python_version()
        VirtualEnvironmentChecker.check_and_warn_virtual_environment()
        print()

    # Default script to analyze
    default_script = "./scripts/setup-azure-credentials.py"

    # Check if default script exists, if not suggest alternatives
    if not os.path.exists(default_script):
        print(f"Default script not found: {default_script}")
        # Look for Python scripts in the scripts directory
        scripts_dir = "./scripts"
        if os.path.exists(scripts_dir):
            python_scripts = [f for f in os.listdir(scripts_dir) if f.endswith(".py")]
            if python_scripts:
                print("Available Python scripts:")
                for script in python_scripts:
                    print(f"  - {script}")
                default_script = os.path.join(scripts_dir, python_scripts[0])
                print(f"Using: {default_script}")
            else:
                print("No Python scripts found in scripts directory")
                return

    # Get script path from command line or use default
    if len(sys.argv) > 1:
        script_path = sys.argv[1]
    else:
        script_path = default_script

    # Convert to absolute path
    script_path = os.path.abspath(script_path)

    # Analyze the script
    modules, badmodules, script_info = analyze_script_dependencies(script_path)

    if modules is None:
        sys.exit(1)

    # Print results
    print(f"\nAnalysis Results:")
    print(f"  Script: {script_info['path']}")
    print(f"  Size: {script_info['size']} bytes")
    print(f"  Total modules found: {len(modules)}")
    print(f"  Missing modules: {len(badmodules)}")

    print_loaded_modules(modules)
    print_missing_modules(badmodules)
    generate_requirements(modules, badmodules)

    print("\n" + "=" * 60)
    print("Module dependency analysis complete!")

    # Exit with error code if there are missing critical modules
    critical_missing = [
        m
        for m in badmodules.keys()
        if any(pkg in m.lower() for pkg in ["azure", "requests"])
    ]
    if critical_missing:
        print(f"\nWarning: Critical modules missing: {', '.join(critical_missing)}")
        sys.exit(1)


if __name__ == "__main__":
    main()
