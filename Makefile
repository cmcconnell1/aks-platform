# Makefile for Azure AKS GitOps Platform
# Provides convenient commands for development, testing, and deployment

.PHONY: help setup setup-dev clean test lint format check install-deps activate docs

# Default target
help: ## Show this help message
	@echo "Azure AKS GitOps Platform - Development Commands"
	@echo "================================================"
	@echo ""
	@echo "Available commands:"
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)
	@echo ""
	@echo "Virtual Environment Commands:"
	@echo "  make setup           Create virtual environment with production dependencies"
	@echo "  make setup-dev       Create virtual environment with development dependencies"
	@echo "  make activate        Show activation command for virtual environment"
	@echo "  make clean           Remove virtual environment and temporary files"
	@echo ""
	@echo "Development Commands:"
	@echo "  make install-deps    Install/update dependencies in existing virtual environment"
	@echo "  make test            Run test suite"
	@echo "  make lint            Run linting checks"
	@echo "  make format          Format code with black and isort"
	@echo "  make check           Run all quality checks (lint + test)"
	@echo ""
	@echo "Documentation Commands:"
	@echo "  make docs            Generate documentation"
	@echo ""
	@echo "Azure Commands:"
	@echo "  make azure-setup     Set up Azure credentials and infrastructure"
	@echo "  make azure-cost      Check Azure costs"
	@echo "  make azure-deploy    Deploy infrastructure (requires environment)"
	@echo ""

# Virtual Environment Setup
setup: ## Create virtual environment with production dependencies
	@echo "Setting up Python virtual environment..."
	./scripts/setup-python-env.sh
	@echo ""
	@echo "Virtual environment created successfully!"
	@echo "To activate: source venv/bin/activate"

setup-dev: ## Create virtual environment with development dependencies
	@echo "Setting up Python virtual environment with development dependencies..."
	./scripts/setup-python-env.sh --dev
	@echo ""
	@echo "Development environment created successfully!"
	@echo "To activate: source venv/bin/activate"

setup-force: ## Force recreate virtual environment
	@echo "Force recreating virtual environment..."
	./scripts/setup-python-env.sh --force --dev

activate: ## Show command to activate virtual environment
	@echo "To activate the virtual environment, run:"
	@echo "  source venv/bin/activate"
	@echo ""
	@echo "Or use the helper script:"
	@echo "  source ./activate-python-env.sh"

# Dependency Management
install-deps: ## Install/update dependencies in existing virtual environment
	@if [ ! -d "venv" ] && [ ! -d ".venv" ]; then \
		echo "No virtual environment found. Run 'make setup' first."; \
		exit 1; \
	fi
	@echo "Installing/updating dependencies..."
	@if [ -f "venv/bin/activate" ]; then \
		. venv/bin/activate && pip install --upgrade pip && pip install -r scripts/requirements.txt; \
	elif [ -f ".venv/bin/activate" ]; then \
		. .venv/bin/activate && pip install --upgrade pip && pip install -r scripts/requirements.txt; \
	fi

install-dev-deps: ## Install development dependencies in existing virtual environment
	@if [ ! -d "venv" ] && [ ! -d ".venv" ]; then \
		echo "No virtual environment found. Run 'make setup-dev' first."; \
		exit 1; \
	fi
	@echo "Installing development dependencies..."
	@if [ -f "venv/bin/activate" ]; then \
		. venv/bin/activate && pip install -r scripts/requirements-dev.txt; \
	elif [ -f ".venv/bin/activate" ]; then \
		. .venv/bin/activate && pip install -r scripts/requirements-dev.txt; \
	fi

# Code Quality
test: ## Run test suite
	@if [ ! -d "venv" ] && [ ! -d ".venv" ]; then \
		echo "No virtual environment found. Run 'make setup-dev' first."; \
		exit 1; \
	fi
	@echo "Running tests..."
	@if [ -f "venv/bin/activate" ]; then \
		. venv/bin/activate && python -m pytest tests/ -v --cov=scripts --cov-report=term-missing; \
	elif [ -f ".venv/bin/activate" ]; then \
		. .venv/bin/activate && python -m pytest tests/ -v --cov=scripts --cov-report=term-missing; \
	fi

lint: ## Run linting checks
	@if [ ! -d "venv" ] && [ ! -d ".venv" ]; then \
		echo "No virtual environment found. Run 'make setup-dev' first."; \
		exit 1; \
	fi
	@echo "Running linting checks..."
	@if [ -f "venv/bin/activate" ]; then \
		. venv/bin/activate && \
		echo "Running flake8..." && flake8 scripts/ && \
		echo "Running pylint..." && pylint scripts/*.py && \
		echo "Running mypy..." && mypy scripts/ --ignore-missing-imports && \
		echo "Running bandit security check..." && bandit -r scripts/ -f json; \
	elif [ -f ".venv/bin/activate" ]; then \
		. .venv/bin/activate && \
		echo "Running flake8..." && flake8 scripts/ && \
		echo "Running pylint..." && pylint scripts/*.py && \
		echo "Running mypy..." && mypy scripts/ --ignore-missing-imports && \
		echo "Running bandit security check..." && bandit -r scripts/ -f json; \
	fi

format: ## Format code with black and isort
	@if [ ! -d "venv" ] && [ ! -d ".venv" ]; then \
		echo "No virtual environment found. Run 'make setup-dev' first."; \
		exit 1; \
	fi
	@echo "Formatting code..."
	@if [ -f "venv/bin/activate" ]; then \
		. venv/bin/activate && \
		echo "Running isort..." && isort scripts/ && \
		echo "Running black..." && black scripts/; \
	elif [ -f ".venv/bin/activate" ]; then \
		. .venv/bin/activate && \
		echo "Running isort..." && isort scripts/ && \
		echo "Running black..." && black scripts/; \
	fi

check: ## Run all quality checks (lint + test)
	@echo "Running all quality checks..."
	@$(MAKE) lint
	@$(MAKE) test
	@echo "All checks completed!"

security-audit: ## Run security audit on dependencies
	@if [ ! -d "venv" ] && [ ! -d ".venv" ]; then \
		echo "No virtual environment found. Run 'make setup-dev' first."; \
		exit 1; \
	fi
	@echo "Running security audit..."
	@if [ -f "venv/bin/activate" ]; then \
		. venv/bin/activate && \
		echo "Running pip-audit..." && pip-audit && \
		echo "Running safety check..." && safety check; \
	elif [ -f ".venv/bin/activate" ]; then \
		. .venv/bin/activate && \
		echo "Running pip-audit..." && pip-audit && \
		echo "Running safety check..." && safety check; \
	fi

# Documentation
docs: ## Generate documentation
	@if [ ! -d "venv" ] && [ ! -d ".venv" ]; then \
		echo "No virtual environment found. Run 'make setup-dev' first."; \
		exit 1; \
	fi
	@echo "Generating documentation..."
	@if [ -f "venv/bin/activate" ]; then \
		. venv/bin/activate && sphinx-build -b html docs/ docs/_build/html; \
	elif [ -f ".venv/bin/activate" ]; then \
		. .venv/bin/activate && sphinx-build -b html docs/ docs/_build/html; \
	fi

# Azure Operations
azure-setup: ## Set up Azure credentials and infrastructure
	@echo "Setting up Azure credentials..."
	./scripts/setup-azure-credentials.sh

azure-cost: ## Check Azure costs
	@echo "Checking Azure costs..."
	./scripts/cost-monitor.sh

azure-deploy: ## Deploy infrastructure (requires ENVIRONMENT variable)
	@if [ -z "$(ENVIRONMENT)" ]; then \
		echo "Error: ENVIRONMENT variable is required"; \
		echo "Usage: make azure-deploy ENVIRONMENT=dev|staging|prod"; \
		exit 1; \
	fi
	@echo "Deploying to $(ENVIRONMENT) environment..."
	./scripts/safe-deployment.sh --environment $(ENVIRONMENT) --component all

# Cleanup
clean: ## Remove virtual environment and temporary files
	@echo "Cleaning up..."
	rm -rf venv/ .venv/ env/
	rm -rf __pycache__/ scripts/__pycache__/
	rm -rf .pytest_cache/ .coverage
	rm -rf docs/_build/
	rm -rf *.egg-info/
	rm -f activate-python-env.sh
	@echo "Cleanup completed!"

clean-all: clean ## Remove all generated files including Terraform state
	@echo "Removing all generated files..."
	rm -rf terraform/.terraform/
	rm -f terraform/*.tfplan
	rm -f terraform/*.tfstate*
	rm -f .env
	rm -f github-actions-credentials.json

# Development workflow shortcuts
dev-setup: setup-dev ## Alias for setup-dev
dev-check: check ## Alias for check
dev-clean: clean ## Alias for clean

# Show current environment status
status: ## Show current environment status
	@echo "Azure AKS GitOps Platform - Environment Status"
	@echo "=============================================="
	@echo ""
	@if [ -d "venv" ]; then \
		echo "OK Virtual environment: venv/ (found)"; \
	elif [ -d ".venv" ]; then \
		echo "OK Virtual environment: .venv/ (found)"; \
	else \
		echo "ERROR Virtual environment: not found"; \
	fi
	@if [ -f "scripts/requirements.txt" ]; then \
		echo "OK Requirements file: scripts/requirements.txt"; \
	else \
		echo "ERROR Requirements file: missing"; \
	fi
	@if [ -f "scripts/requirements-dev.txt" ]; then \
		echo "OK Dev requirements: scripts/requirements-dev.txt"; \
	else \
		echo "ERROR Dev requirements: missing"; \
	fi
	@if command -v az >/dev/null 2>&1; then \
		echo "OK Azure CLI: installed"; \
	else \
		echo "ERROR Azure CLI: not installed"; \
	fi
	@if command -v terraform >/dev/null 2>&1; then \
		echo "OK Terraform: installed"; \
	else \
		echo "ERROR Terraform: not installed"; \
	fi
	@if command -v kubectl >/dev/null 2>&1; then \
		echo "OK kubectl: installed"; \
	else \
		echo "ERROR kubectl: not installed"; \
	fi

