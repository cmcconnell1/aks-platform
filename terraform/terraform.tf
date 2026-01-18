# Terraform configuration block
terraform {
  required_version = ">= 1.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.0"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.14"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.0"
    }
  }

  # Backend configuration for remote state
  # This will be configured per environment
  backend "azurerm" {
    # Configuration will be provided via backend config files
    # or environment variables during terraform init
  }
}

# Configure the Azure Provider
provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }

    resource_group {
      prevent_deletion_if_contains_resources = false
    }

    virtual_machine {
      delete_os_disk_on_deletion     = true
      skip_shutdown_and_force_delete = false
    }
  }
}

# Configure the Azure Active Directory Provider
provider "azuread" {
}

# Configure Kubernetes provider (will be configured after AKS creation)
provider "kubernetes" {
  # Configuration will be set dynamically after AKS cluster creation
}

# Configure Helm provider (will be configured after AKS creation)
provider "helm" {
  # Configuration will be set dynamically after AKS cluster creation
}

# Configure kubectl provider (will be configured after AKS creation)
provider "kubectl" {
  # Configuration will be set dynamically after AKS cluster creation
}

# Configure HTTP provider (for data sources)
provider "http" {
  # No configuration needed
}

# Data sources for current Azure context
data "azurerm_client_config" "current" {}

data "azuread_client_config" "current" {}

# Random suffix for unique resource naming
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}
