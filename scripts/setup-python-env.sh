#!/bin/bash

# Python Virtual Environment Setup Script for Azure AKS GitOps Platform
#
# This script sets up a Python virtual environment with all required dependencies
# for the Azure AKS GitOps platform scripts and tools.
#
# Usage:
#   ./scripts/setup-python-env.sh [options]
#
# Options:
#   --venv-name NAME    Name of virtual environment directory (default: venv)
#   --python-version    Python version to use (default: python3)
#   --dev               Install development dependencies
#   --force             Force recreation of virtual environment if it exists
#   --help              Show this help message
#
# Examples:
#   ./scripts/setup-python-env.sh                    # Basic setup
#   ./scripts/setup-python-env.sh --dev             # Include dev dependencies
#   ./scripts/setup-python-env.sh --venv-name .venv # Use .venv directory
#   ./scripts/setup-python-env.sh --force           # Recreate existing environment

set -euo pipefail

# Default configuration
VENV_NAME="venv"
PYTHON_CMD="python3"
INSTALL_DEV=false
FORCE_RECREATE=false
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Help function
show_help() {
    cat << EOF
Python Virtual Environment Setup Script

This script sets up a Python virtual environment with all required dependencies
for the Azure AKS GitOps platform scripts and tools.

Usage: $0 [options]

Options:
    --venv-name NAME     Name of virtual environment directory (default: venv)
    --python-version     Python version to use (default: python3)
    --dev                Install development dependencies
    --force              Force recreation of virtual environment if it exists
    --help               Show this help message

Examples:
    $0                           # Basic setup
    $0 --dev                     # Include dev dependencies
    $0 --venv-name .venv         # Use .venv directory
    $0 --force                   # Recreate existing environment

Requirements:
    - Python 3.7+ installed
    - pip package manager
    - Internet connection for package downloads

The script will:
    1. Check Python installation and version
    2. Create virtual environment in specified directory
    3. Upgrade pip to latest version
    4. Install production dependencies from requirements.txt
    5. Install development dependencies if --dev flag is used
    6. Create activation helper scripts
    7. Provide usage instructions

Virtual Environment Structure:
    $VENV_NAME/
    ├── bin/activate (Linux/macOS) or Scripts/activate (Windows)
    ├── lib/python*/site-packages/
    └── pyvenv.cfg

After setup, activate the environment with:
    source $VENV_NAME/bin/activate    # Linux/macOS
    $VENV_NAME\\Scripts\\activate      # Windows

EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --venv-name)
                VENV_NAME="$2"
                shift 2
                ;;
            --python-version)
                PYTHON_CMD="$2"
                shift 2
                ;;
            --dev)
                INSTALL_DEV=true
                shift
                ;;
            --force)
                FORCE_RECREATE=true
                shift
                ;;
            --help)
                show_help
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done
}

# Check Python installation and version
check_python() {
    print_status "Checking Python installation..."
    
    if ! command -v "$PYTHON_CMD" >/dev/null 2>&1; then
        print_error "Python command '$PYTHON_CMD' not found"
        print_status "Please install Python 3.7+ and try again"
        print_status "Installation guides:"
        print_status "  macOS: brew install python3"
        print_status "  Ubuntu/Debian: sudo apt update && sudo apt install python3 python3-pip python3-venv"
        print_status "  CentOS/RHEL: sudo yum install python3 python3-pip"
        exit 1
    fi
    
    # Check Python version
    local python_version
    python_version=$("$PYTHON_CMD" -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
    local major minor
    major=$(echo "$python_version" | cut -d. -f1)
    minor=$(echo "$python_version" | cut -d. -f2)
    
    if [[ $major -lt 3 ]] || [[ $major -eq 3 && $minor -lt 7 ]]; then
        print_error "Python 3.7+ is required (found: $python_version)"
        print_status "Please upgrade Python and try again"
        exit 1
    fi
    
    print_success "Python $python_version found"
}

# Check if virtual environment module is available
check_venv_module() {
    print_status "Checking virtual environment support..."
    
    if ! "$PYTHON_CMD" -m venv --help >/dev/null 2>&1; then
        print_error "Python venv module not available"
        print_status "Install with:"
        print_status "  Ubuntu/Debian: sudo apt install python3-venv"
        print_status "  CentOS/RHEL: sudo yum install python3-venv"
        exit 1
    fi
    
    print_success "Virtual environment support available"
}

# Create or recreate virtual environment
setup_virtual_environment() {
    cd "$PROJECT_ROOT"
    
    if [[ -d "$VENV_NAME" ]]; then
        if [[ "$FORCE_RECREATE" == "true" ]]; then
            print_warning "Removing existing virtual environment: $VENV_NAME"
            rm -rf "$VENV_NAME"
        else
            print_warning "Virtual environment '$VENV_NAME' already exists"
            print_status "Use --force to recreate or choose a different name with --venv-name"
            print_status "To activate existing environment: source $VENV_NAME/bin/activate"
            exit 1
        fi
    fi
    
    print_status "Creating virtual environment: $VENV_NAME"
    "$PYTHON_CMD" -m venv "$VENV_NAME"
    
    print_success "Virtual environment created successfully"
}

# Activate virtual environment and upgrade pip
activate_and_upgrade() {
    print_status "Activating virtual environment and upgrading pip..."
    
    # Source the activation script
    source "$PROJECT_ROOT/$VENV_NAME/bin/activate"
    
    # Upgrade pip to latest version
    python -m pip install --upgrade pip
    
    print_success "Virtual environment activated and pip upgraded"
}

# Install dependencies
install_dependencies() {
    print_status "Installing Python dependencies..."
    
    # Install production dependencies
    if [[ -f "$SCRIPT_DIR/requirements.txt" ]]; then
        print_status "Installing production dependencies from requirements.txt..."
        pip install -r "$SCRIPT_DIR/requirements.txt"
        print_success "Production dependencies installed"
    else
        print_warning "requirements.txt not found in scripts directory"
    fi
    
    # Install development dependencies if requested
    if [[ "$INSTALL_DEV" == "true" ]]; then
        if [[ -f "$SCRIPT_DIR/requirements-dev.txt" ]]; then
            print_status "Installing development dependencies from requirements-dev.txt..."
            pip install -r "$SCRIPT_DIR/requirements-dev.txt"
            print_success "Development dependencies installed"
        else
            print_warning "requirements-dev.txt not found, skipping development dependencies"
        fi
    fi
}

# Create activation helper scripts
create_helpers() {
    print_status "Creating activation helper scripts..."
    
    # Create activation script for easy sourcing
    cat > "$PROJECT_ROOT/activate-python-env.sh" << 'EOF'
#!/bin/bash
# Helper script to activate Python virtual environment
# Usage: source ./activate-python-env.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_NAME="venv"

# Check for different virtual environment names
if [[ -d "$SCRIPT_DIR/.venv" ]]; then
    VENV_NAME=".venv"
elif [[ -d "$SCRIPT_DIR/venv" ]]; then
    VENV_NAME="venv"
elif [[ -d "$SCRIPT_DIR/env" ]]; then
    VENV_NAME="env"
else
    echo "Error: No virtual environment found"
    echo "Run ./scripts/setup-python-env.sh to create one"
    return 1
fi

if [[ -f "$SCRIPT_DIR/$VENV_NAME/bin/activate" ]]; then
    source "$SCRIPT_DIR/$VENV_NAME/bin/activate"
    echo "Python virtual environment activated: $VENV_NAME"
    echo "Python version: $(python --version)"
    echo "Pip version: $(pip --version)"
else
    echo "Error: Virtual environment activation script not found"
    echo "Run ./scripts/setup-python-env.sh to create virtual environment"
    return 1
fi
EOF
    
    chmod +x "$PROJECT_ROOT/activate-python-env.sh"
    print_success "Activation helper created: activate-python-env.sh"
}

# Display final instructions
show_final_instructions() {
    print_success "Python virtual environment setup completed!"
    echo
    print_status "Virtual environment location: $PROJECT_ROOT/$VENV_NAME"
    print_status "Python version: $(python --version)"
    print_status "Pip version: $(pip --version)"
    echo
    print_status "To activate the virtual environment:"
    echo "  source $VENV_NAME/bin/activate"
    echo "  # OR use the helper script:"
    echo "  source ./activate-python-env.sh"
    echo
    print_status "To deactivate the virtual environment:"
    echo "  deactivate"
    echo
    print_status "To install additional packages:"
    echo "  # First activate the environment, then:"
    echo "  pip install package-name"
    echo
    print_status "To update requirements.txt with new packages:"
    echo "  pip freeze > scripts/requirements.txt"
    echo
    if [[ "$INSTALL_DEV" == "false" ]]; then
        print_status "To install development dependencies later:"
        echo "  ./scripts/setup-python-env.sh --dev"
    fi
}

# Main execution
main() {
    echo "Python Virtual Environment Setup for Azure AKS GitOps Platform"
    echo "=============================================================="
    echo
    
    parse_args "$@"
    check_python
    check_venv_module
    setup_virtual_environment
    activate_and_upgrade
    install_dependencies
    create_helpers
    show_final_instructions
}

# Run main function with all arguments
main "$@"
