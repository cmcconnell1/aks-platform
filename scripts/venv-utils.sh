#!/bin/bash

# Virtual Environment Utilities for Azure AKS GitOps Platform Shell Scripts
#
# This file provides shared functions for virtual environment detection,
# activation, and Python package management across shell scripts.
#
# Usage:
#   source scripts/venv-utils.sh
#   check_virtual_environment
#   install_python_packages_with_venv

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions (can be overridden by sourcing script)
if ! declare -f print_status >/dev/null 2>&1; then
    print_status() {
        echo -e "${BLUE}[INFO]${NC} $1"
    }
fi

if ! declare -f print_success >/dev/null 2>&1; then
    print_success() {
        echo -e "${GREEN}[SUCCESS]${NC} $1"
    }
fi

if ! declare -f print_warning >/dev/null 2>&1; then
    print_warning() {
        echo -e "${YELLOW}[WARNING]${NC} $1"
    }
fi

if ! declare -f print_error >/dev/null 2>&1; then
    print_error() {
        echo -e "${RED}[ERROR]${NC} $1"
    }
fi

# Check if running in a virtual environment
is_virtual_environment() {
    # Check for VIRTUAL_ENV environment variable
    if [[ -n "$VIRTUAL_ENV" ]]; then
        return 0
    fi
    
    # Check if python executable is in a virtual environment path
    local python_path
    python_path=$(which python3 2>/dev/null || which python 2>/dev/null)
    
    if [[ -n "$python_path" ]]; then
        # Check if path contains common virtual environment indicators
        if [[ "$python_path" == *"/venv/"* ]] || \
           [[ "$python_path" == *"/.venv/"* ]] || \
           [[ "$python_path" == *"/env/"* ]] || \
           [[ "$python_path" == *"/virtualenv/"* ]]; then
            return 0
        fi
    fi
    
    return 1
}

# Find virtual environment directories in the project
find_virtual_environments() {
    local project_root="${1:-$(pwd)}"
    local venv_dirs=()
    
    # Common virtual environment directory names
    local common_names=("venv" ".venv" "env" ".env" "virtualenv")
    
    for name in "${common_names[@]}"; do
        local venv_path="$project_root/$name"
        if [[ -d "$venv_path" ]]; then
            # Check if it looks like a virtual environment
            if [[ -f "$venv_path/bin/activate" ]] || [[ -f "$venv_path/Scripts/activate" ]]; then
                venv_dirs+=("$venv_path")
            fi
        fi
    done
    
    printf '%s\n' "${venv_dirs[@]}"
}

# Get the path to the virtual environment activation script
get_venv_activation_script() {
    local venv_path="$1"
    
    if [[ -f "$venv_path/bin/activate" ]]; then
        echo "$venv_path/bin/activate"
    elif [[ -f "$venv_path/Scripts/activate" ]]; then
        echo "$venv_path/Scripts/activate"
    else
        return 1
    fi
}

# Check virtual environment status and provide recommendations
check_virtual_environment() {
    local quiet="${1:-false}"
    
    if [[ "$quiet" != "true" ]]; then
        print_status "Checking Python virtual environment..."
    fi
    
    if is_virtual_environment; then
        if [[ "$quiet" != "true" ]]; then
            print_success "Running in virtual environment: $VIRTUAL_ENV"
        fi
        return 0
    else
        if [[ "$quiet" != "true" ]]; then
            print_warning "Not running in a virtual environment"
            print_status "Virtual environments are recommended for Python development"
            
            # Look for existing virtual environments
            local project_root
            project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
            local found_venvs=()
            while IFS= read -r line; do
                found_venvs+=("$line")
            done < <(find_virtual_environments "$project_root")
            
            if [[ ${#found_venvs[@]} -gt 0 ]]; then
                print_status "Found existing virtual environments:"
                for venv_dir in "${found_venvs[@]}"; do
                    echo "  - $venv_dir"
                done
                local activation_script
                activation_script=$(get_venv_activation_script "${found_venvs[0]}")
                if [[ -n "$activation_script" ]]; then
                    print_status "To activate, run:"
                    echo "  source $activation_script"
                    echo "  # OR use the helper script:"
                    echo "  source ./activate-python-env.sh"
                fi
            else
                print_status "No virtual environments found"
                print_status "Create one with:"
                echo "  ./scripts/setup-python-env.sh"
                echo "  # OR manually:"
                echo "  python3 -m venv venv && source venv/bin/activate"
            fi
            echo
        fi
        return 1
    fi
}

# Activate virtual environment if available
activate_virtual_environment() {
    local project_root
    project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    
    # If already in virtual environment, nothing to do
    if is_virtual_environment; then
        return 0
    fi
    
    # Find available virtual environments
    local found_venvs=()
    while IFS= read -r line; do
        found_venvs+=("$line")
    done < <(find_virtual_environments "$project_root")
    
    if [[ ${#found_venvs[@]} -eq 0 ]]; then
        return 1
    fi
    
    # Try to activate the first found virtual environment
    local activation_script
    activation_script=$(get_venv_activation_script "${found_venvs[0]}")
    
    if [[ -n "$activation_script" ]]; then
        print_status "Activating virtual environment: ${found_venvs[0]}"
        # Note: This won't work in the current shell context when sourced
        # The calling script needs to handle activation
        echo "source $activation_script"
        return 0
    fi
    
    return 1
}

# Install Python packages with virtual environment awareness
install_python_packages_with_venv() {
    local packages=("$@")
    local use_requirements=false
    local requirements_file=""
    
    # Check if first argument is a requirements file
    if [[ ${#packages[@]} -eq 1 && "${packages[0]}" == *"requirements"* && -f "${packages[0]}" ]]; then
        use_requirements=true
        requirements_file="${packages[0]}"
    fi
    
    # Check virtual environment status
    local in_venv=false
    if is_virtual_environment; then
        in_venv=true
        print_success "Installing packages in virtual environment: $VIRTUAL_ENV"
    else
        print_warning "Installing packages outside virtual environment"
        print_status "Consider activating a virtual environment for better dependency management"
        
        # Look for existing virtual environments
        local project_root
        project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
        local found_venvs=()
        while IFS= read -r line; do
            found_venvs+=("$line")
        done < <(find_virtual_environments "$project_root")
        
        if [[ ${#found_venvs[@]} -gt 0 ]]; then
            print_status "Found virtual environment: ${found_venvs[0]}"
            print_status "To use it, run: source ${found_venvs[0]}/bin/activate"
        else
            print_status "Create virtual environment with: ./scripts/setup-python-env.sh"
        fi
        echo
    fi
    
    # Install packages
    if [[ "$use_requirements" == "true" ]]; then
        print_status "Installing packages from $requirements_file..."
        if python3 -m pip install -r "$requirements_file" --quiet; then
            print_success "Packages installed successfully from $requirements_file"
            return 0
        else
            print_error "Failed to install packages from $requirements_file"
            return 1
        fi
    else
        print_status "Installing packages: ${packages[*]}"
        if python3 -m pip install "${packages[@]}" --quiet; then
            print_success "Packages installed successfully"
            return 0
        else
            print_error "Failed to install packages: ${packages[*]}"
            return 1
        fi
    fi
}

# Check if Python packages are installed
check_python_packages() {
    local packages=("$@")
    local missing_packages=()
    
    for package in "${packages[@]}"; do
        if ! python3 -c "import $package" >/dev/null 2>&1; then
            missing_packages+=("$package")
        fi
    done
    
    if [[ ${#missing_packages[@]} -eq 0 ]]; then
        return 0
    else
        echo "${missing_packages[@]}"
        return 1
    fi
}

# Enhanced dependency installation with virtual environment support
install_dependencies_enhanced() {
    local requirements_file="${1:-$(dirname "${BASH_SOURCE[0]}")/requirements.txt}"
    local fallback_packages=("${@:2}")
    
    print_status "Checking Python dependencies..."
    
    # Check virtual environment
    check_virtual_environment true
    
    # Check if requirements file exists
    if [[ -f "$requirements_file" ]]; then
        print_status "Found requirements file: $requirements_file"
        
        # Try to install from requirements file
        if install_python_packages_with_venv "$requirements_file"; then
            return 0
        else
            print_warning "Failed to install from requirements file"
            if [[ ${#fallback_packages[@]} -gt 0 ]]; then
                print_status "Trying fallback packages..."
                install_python_packages_with_venv "${fallback_packages[@]}"
            fi
        fi
    else
        print_warning "Requirements file not found: $requirements_file"
        if [[ ${#fallback_packages[@]} -gt 0 ]]; then
            print_status "Installing fallback packages..."
            install_python_packages_with_venv "${fallback_packages[@]}"
        fi
    fi
}

# Show virtual environment status
show_venv_status() {
    echo "Virtual Environment Status:"
    echo "=========================="
    
    if is_virtual_environment; then
        echo "OK Active virtual environment: $VIRTUAL_ENV"
        echo "OK Python executable: $(which python3)"
        echo "OK Pip version: $(python3 -m pip --version 2>/dev/null || echo 'Not available')"
    else
        echo "ERROR No active virtual environment"
        echo "  Python executable: $(which python3)"
        echo "  Pip version: $(python3 -m pip --version 2>/dev/null || echo 'Not available')"
        
        local project_root
        project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
        local found_venvs=()
        while IFS= read -r line; do
            found_venvs+=("$line")
        done < <(find_virtual_environments "$project_root")
        
        if [[ ${#found_venvs[@]} -gt 0 ]]; then
            echo "  Available virtual environments:"
            for venv_dir in "${found_venvs[@]}"; do
                echo "    - $venv_dir"
            done
        else
            echo "  No virtual environments found"
        fi
    fi
    echo
}
