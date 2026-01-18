# Azure to GitHub OIDC Federation Setup Guide

This guide explains how to configure secure, secretless authentication between GitHub Actions and Azure using OpenID Connect (OIDC) workload identity federation.

## Table of Contents

1. [Overview](#overview)
2. [Why OIDC Federation](#why-oidc-federation)
3. [How It Works](#how-it-works)
4. [Quick Setup](#quick-setup)
5. [Manual Setup](#manual-setup)
6. [GitHub Workflow Configuration](#github-workflow-configuration)
7. [Migration from Service Principal Secrets](#migration-from-service-principal-secrets)
8. [Security Best Practices](#security-best-practices)
9. [Troubleshooting](#troubleshooting)

## Overview

OIDC (OpenID Connect) federation allows GitHub Actions workflows to authenticate with Azure without storing long-lived credentials. Instead of using a client secret that must be rotated periodically, Azure issues short-lived tokens directly to GitHub Actions during workflow execution.

### Key Concepts

| Term | Description |
|------|-------------|
| **Workload Identity** | Azure AD feature that allows external identity providers (like GitHub) to authenticate |
| **Federated Credential** | Configuration that trusts tokens from GitHub Actions |
| **ID Token** | Short-lived token issued by GitHub during workflow execution |
| **Subject Claim** | Unique identifier for the GitHub context (repo, branch, environment) |

## Why OIDC Federation

### Traditional Approach (Service Principal Secrets)

```
[GitHub Secrets] --> [Client Secret] --> [Azure AD] --> [Azure Resources]
                           |
                           v
                    Stored in GitHub
                    Must be rotated manually
                    Can be leaked/exposed
```

**Problems with Traditional Approach:**
- Long-lived secrets (typically valid for 1-2 years)
- Manual rotation required
- Secrets stored in multiple places
- Risk of secret exposure
- No automatic expiration

### OIDC Approach (Recommended)

```
[GitHub Actions] --> [ID Token Request] --> [GitHub OIDC Provider]
                                                    |
                                                    v
                                            [Short-lived ID Token]
                                                    |
                                                    v
                     [Azure AD validates token] <---+
                           |
                           v
                    [Access Token issued]
                           |
                           v
                    [Azure Resources]
```

**Benefits of OIDC:**

| Benefit | Description |
|---------|-------------|
| No Stored Secrets | No client secrets to manage or rotate |
| Short-lived Tokens | Tokens expire automatically (~10 minutes) |
| Automatic Rotation | Every workflow run gets a fresh token |
| Scoped Access | Tokens are tied to specific repos/branches/environments |
| Auditable | All authentication events logged in Azure AD |
| Reduced Attack Surface | No secrets that can be leaked or stolen |

## How It Works

### Authentication Flow

```
1. Workflow starts
   |
   v
2. GitHub Actions requests ID token from GitHub OIDC Provider
   |
   v
3. GitHub issues ID token with claims:
   - iss: https://token.actions.githubusercontent.com
   - sub: repo:org/repo:environment:prod
   - aud: api://AzureADTokenExchange
   |
   v
4. Workflow sends ID token to Azure AD
   |
   v
5. Azure AD validates:
   - Token signature
   - Issuer claim (GitHub)
   - Subject claim (matches federated credential)
   - Audience claim
   |
   v
6. Azure AD issues access token for Azure resources
   |
   v
7. Workflow uses access token to manage Azure resources
```

### Subject Claim Patterns

Azure validates the `sub` claim in the GitHub token against the federated credential configuration:

| Context | Subject Pattern | Example |
|---------|----------------|---------|
| Branch | `repo:ORG/REPO:ref:refs/heads/BRANCH` | `repo:myorg/myrepo:ref:refs/heads/main` |
| Environment | `repo:ORG/REPO:environment:ENV` | `repo:myorg/myrepo:environment:prod` |
| Pull Request | `repo:ORG/REPO:pull_request` | `repo:myorg/myrepo:pull_request` |
| Tag | `repo:ORG/REPO:ref:refs/tags/TAG` | `repo:myorg/myrepo:ref:refs/tags/v1.0.0` |

## Quick Setup

### Prerequisites

- Azure CLI installed and authenticated
- GitHub CLI installed and authenticated
- Owner/Contributor access on Azure subscription
- Admin access to GitHub repository

### Automated Setup

```bash
# Make script executable
chmod +x scripts/setup-azure-oidc.sh

# Run the setup script
./scripts/setup-azure-oidc.sh

# Or specify options
./scripts/setup-azure-oidc.sh --environment prod
./scripts/setup-azure-oidc.sh --app-name my-custom-app --environment all

# Dry run to see what would be done
./scripts/setup-azure-oidc.sh --dry-run
```

The script will:
1. Create an Azure AD application
2. Create a service principal
3. Configure federated credentials for:
   - Main branch
   - Each environment (dev, staging, prod)
   - Pull requests
4. Assign necessary Azure roles
5. Configure GitHub secrets

## Manual Setup

### Step 1: Create Azure AD Application

```bash
# Login to Azure
az login

# Create the application
APP_NAME="aks-platform-github-oidc"
APP_ID=$(az ad app create --display-name "$APP_NAME" --query appId -o tsv)
echo "Application ID: $APP_ID"

# Create service principal
SP_OBJECT_ID=$(az ad sp create --id "$APP_ID" --query id -o tsv)
echo "Service Principal Object ID: $SP_OBJECT_ID"
```

### Step 2: Create Federated Credentials

```bash
# Set your GitHub organization and repo
GITHUB_ORG="your-org"
GITHUB_REPO="your-repo"

# Create credential for main branch
az ad app federated-credential create \
    --id "$APP_ID" \
    --parameters '{
        "name": "github-main-branch",
        "issuer": "https://token.actions.githubusercontent.com",
        "subject": "repo:'"$GITHUB_ORG/$GITHUB_REPO"':ref:refs/heads/main",
        "description": "GitHub Actions for main branch",
        "audiences": ["api://AzureADTokenExchange"]
    }'

# Create credential for production environment
az ad app federated-credential create \
    --id "$APP_ID" \
    --parameters '{
        "name": "github-env-prod",
        "issuer": "https://token.actions.githubusercontent.com",
        "subject": "repo:'"$GITHUB_ORG/$GITHUB_REPO"':environment:prod",
        "description": "GitHub Actions for production environment",
        "audiences": ["api://AzureADTokenExchange"]
    }'

# Create credential for pull requests
az ad app federated-credential create \
    --id "$APP_ID" \
    --parameters '{
        "name": "github-pull-requests",
        "issuer": "https://token.actions.githubusercontent.com",
        "subject": "repo:'"$GITHUB_ORG/$GITHUB_REPO"':pull_request",
        "description": "GitHub Actions for pull requests",
        "audiences": ["api://AzureADTokenExchange"]
    }'
```

### Step 3: Assign Azure Roles

```bash
SUBSCRIPTION_ID=$(az account show --query id -o tsv)

# Assign Contributor role
az role assignment create \
    --assignee-object-id "$SP_OBJECT_ID" \
    --assignee-principal-type ServicePrincipal \
    --role "Contributor" \
    --scope "/subscriptions/$SUBSCRIPTION_ID"

# Assign User Access Administrator (if needed for RBAC)
az role assignment create \
    --assignee-object-id "$SP_OBJECT_ID" \
    --assignee-principal-type ServicePrincipal \
    --role "User Access Administrator" \
    --scope "/subscriptions/$SUBSCRIPTION_ID"
```

### Step 4: Configure GitHub Secrets

```bash
TENANT_ID=$(az account show --query tenantId -o tsv)

# Set secrets using GitHub CLI
gh secret set AZURE_CLIENT_ID --body "$APP_ID"
gh secret set AZURE_TENANT_ID --body "$TENANT_ID"
gh secret set AZURE_SUBSCRIPTION_ID --body "$SUBSCRIPTION_ID"
```

## GitHub Workflow Configuration

### Basic OIDC Login

```yaml
name: Deploy to Azure

on:
  push:
    branches: [main]

permissions:
  id-token: write    # Required for requesting the OIDC token
  contents: read     # Required for actions/checkout

jobs:
  deploy:
    runs-on: ubuntu-latest
    environment: prod  # Must match federated credential configuration

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Azure Login (OIDC)
        uses: azure/login@v2
        with:
          client-id: ${{ secrets.AZURE_CLIENT_ID }}
          tenant-id: ${{ secrets.AZURE_TENANT_ID }}
          subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}

      - name: Run Azure CLI commands
        run: |
          az account show
          az group list --output table
```

### Terraform with OIDC

```yaml
jobs:
  terraform:
    runs-on: ubuntu-latest
    environment: prod

    permissions:
      id-token: write
      contents: read

    env:
      ARM_CLIENT_ID: ${{ secrets.AZURE_CLIENT_ID }}
      ARM_SUBSCRIPTION_ID: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
      ARM_TENANT_ID: ${{ secrets.AZURE_TENANT_ID }}
      ARM_USE_OIDC: true  # Tell Terraform to use OIDC

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Azure Login
        uses: azure/login@v2
        with:
          client-id: ${{ secrets.AZURE_CLIENT_ID }}
          tenant-id: ${{ secrets.AZURE_TENANT_ID }}
          subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}

      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v3

      - name: Terraform Init
        run: terraform init
        working-directory: terraform

      - name: Terraform Plan
        run: terraform plan
        working-directory: terraform
```

### Multi-Environment Deployment

```yaml
jobs:
  deploy-dev:
    runs-on: ubuntu-latest
    environment: dev
    permissions:
      id-token: write
      contents: read
    steps:
      - uses: azure/login@v2
        with:
          client-id: ${{ secrets.AZURE_CLIENT_ID }}
          tenant-id: ${{ secrets.AZURE_TENANT_ID }}
          subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
      # ... deploy steps

  deploy-staging:
    runs-on: ubuntu-latest
    environment: staging
    needs: deploy-dev
    permissions:
      id-token: write
      contents: read
    steps:
      - uses: azure/login@v2
        with:
          client-id: ${{ secrets.AZURE_CLIENT_ID }}
          tenant-id: ${{ secrets.AZURE_TENANT_ID }}
          subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
      # ... deploy steps

  deploy-prod:
    runs-on: ubuntu-latest
    environment: prod
    needs: deploy-staging
    permissions:
      id-token: write
      contents: read
    steps:
      - uses: azure/login@v2
        with:
          client-id: ${{ secrets.AZURE_CLIENT_ID }}
          tenant-id: ${{ secrets.AZURE_TENANT_ID }}
          subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
      # ... deploy steps
```

## Migration from Service Principal Secrets

### Step 1: Set Up OIDC (While Keeping Secrets)

Run the OIDC setup script while keeping your existing secrets as a fallback:

```bash
./scripts/setup-azure-oidc.sh
```

### Step 2: Update Workflows Incrementally

Update one workflow at a time, starting with non-production:

```yaml
# Before (secret-based)
- uses: azure/login@v1
  with:
    creds: ${{ secrets.AZURE_CREDENTIALS }}

# After (OIDC-based)
- uses: azure/login@v2
  with:
    client-id: ${{ secrets.AZURE_CLIENT_ID }}
    tenant-id: ${{ secrets.AZURE_TENANT_ID }}
    subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
```

Add required permissions:

```yaml
permissions:
  id-token: write
  contents: read
```

### Step 3: Test Thoroughly

1. Run PR workflows to test PR credentials
2. Deploy to dev environment
3. Deploy to staging environment
4. Deploy to production environment

### Step 4: Remove Old Secrets

Once all workflows are migrated and tested:

```bash
# Remove old secret-based credentials
gh secret delete ARM_CLIENT_SECRET
gh secret delete AZURE_CREDENTIALS

# For each environment
for env in dev staging prod; do
    gh secret delete ARM_CLIENT_SECRET --env "$env"
    gh secret delete AZURE_CREDENTIALS --env "$env"
done
```

### Step 5: Revoke Service Principal Secret

```bash
# Get the service principal ID
SP_ID=$(az ad sp list --display-name "your-old-sp-name" --query "[0].id" -o tsv)

# Remove all credentials
az ad sp credential reset --id "$SP_ID" --years 0
```

## Security Best Practices

### 1. Principle of Least Privilege

Create separate federated credentials for each purpose:

```bash
# Separate credentials for different branches
az ad app federated-credential create --id "$APP_ID" --parameters '{
    "name": "feature-branches",
    "subject": "repo:org/repo:ref:refs/heads/feature/*",
    ...
}'
```

### 2. Environment Protection Rules

Configure GitHub environment protection:

```bash
# Require reviewers for production
gh api --method PUT "/repos/ORG/REPO/environments/prod" \
    --field "reviewers[][type]=User" \
    --field "reviewers[][id]=123456"
```

### 3. Scope Azure Roles Appropriately

```bash
# Production: Read-only for planning
az role assignment create \
    --assignee-object-id "$SP_OBJECT_ID" \
    --role "Reader" \
    --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/prod-rg"

# Create separate SP for write operations
```

### 4. Monitor Authentication Events

Enable Azure AD sign-in logging:

```bash
az monitor diagnostic-settings create \
    --name "github-oidc-logs" \
    --resource "/providers/Microsoft.aadiam/tenants/$TENANT_ID" \
    --workspace "$LOG_ANALYTICS_WORKSPACE_ID" \
    --logs '[{"category": "SignInLogs", "enabled": true}]'
```

### 5. Regular Audits

```bash
# List all federated credentials
az ad app federated-credential list --id "$APP_ID" -o table

# Review role assignments
az role assignment list --assignee "$SP_OBJECT_ID" -o table
```

## Troubleshooting

### Error: AADSTS70021 - No matching federated identity record found

**Cause:** The subject claim in the GitHub token doesn't match any federated credential.

**Solution:**
1. Verify the workflow is using the correct environment
2. Check the federated credential subject pattern:

```bash
# List credentials
az ad app federated-credential list --id "$APP_ID" --query "[].{Name:name, Subject:subject}" -o table
```

3. Ensure the workflow has `permissions: id-token: write`

### Error: AADSTS700016 - Application not found

**Cause:** The client ID is incorrect or the application doesn't exist.

**Solution:**
```bash
# Verify application exists
az ad app show --id "$AZURE_CLIENT_ID"
```

### Error: AADSTS700024 - Client assertion is not within its valid time range

**Cause:** Clock skew between GitHub and Azure.

**Solution:** This is usually transient. Retry the workflow.

### Error: Missing permissions for id-token

**Cause:** Workflow doesn't have the required permissions.

**Solution:** Add permissions block:

```yaml
permissions:
  id-token: write
  contents: read
```

### Terraform Error: ARM_USE_OIDC not recognized

**Cause:** Using an older version of the AzureRM provider.

**Solution:** Update to AzureRM provider 3.0+ or use environment variables:

```yaml
env:
  ARM_USE_OIDC: true
  ARM_CLIENT_ID: ${{ secrets.AZURE_CLIENT_ID }}
  ARM_SUBSCRIPTION_ID: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
  ARM_TENANT_ID: ${{ secrets.AZURE_TENANT_ID }}
```

### Debug OIDC Token Claims

Add a debug step to see the token claims:

```yaml
- name: Debug OIDC Token
  run: |
    curl -s -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" \
      "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=api://AzureADTokenExchange" | \
      jq -r '.value | split(".")[1] | @base64d | fromjson'
```

## Related Documentation

- [Deployment Guide](./deployment-guide.md)
- [Security Guide](./security.md)
- [GitHub Actions Workflows](.github/workflows/)
- [Microsoft OIDC Documentation](https://learn.microsoft.com/en-us/azure/active-directory/workload-identities/workload-identity-federation)
- [GitHub OIDC Documentation](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-azure)
