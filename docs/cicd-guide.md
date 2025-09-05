# CI/CD Pipeline Guide

This guide explains the GitHub Actions workflows for automated infrastructure management, security scanning, and deployment.

## Overview

The project includes three main workflows:

1. **Terraform Plan** - Validates and plans infrastructure changes on pull requests
2. **Terraform Deploy** - Deploys infrastructure changes when code is merged
3. **Drift Detection** - Monitors for configuration drift on a schedule

## Workflow Details

### 1. Terraform Plan Workflow

**Trigger**: Pull requests to main/develop branches
**File**: `.github/workflows/terraform-plan.yml`

**Features**:
- Multi-environment planning (dev, staging, prod)
- Terraform validation and formatting checks
- Security scanning with Checkov and TFSec
- Cost estimation with Infracost
- Automated PR comments with results

**Steps**:
1. Checkout code and setup tools
2. Authenticate with Azure
3. Run Terraform format check
4. Initialize Terraform with environment-specific backend
5. Validate Terraform configuration
6. Generate Terraform plan
7. Upload plan artifacts
8. Run security scans
9. Generate cost estimates
10. Comment results on PR

### 2. Terraform Deploy Workflow

**Trigger**: Push to main branch or manual dispatch
**File**: `.github/workflows/terraform-deploy.yml`

**Features**:
- Environment-specific deployments
- Manual approval for staging/prod (via GitHub environments)
- Post-deployment verification
- Infrastructure testing
- Deployment summaries

**Steps**:
1. Checkout code and setup tools
2. Authenticate with Azure
3. Initialize Terraform
4. Generate and apply Terraform plan
5. Configure kubectl access
6. Verify deployment health
7. Run post-deployment tests
8. Generate deployment summary

### 3. Drift Detection Workflow

**Trigger**: Daily schedule (6 AM UTC) or manual dispatch
**File**: `.github/workflows/terraform-drift-detection.yml`

**Features**:
- Automated drift detection across all environments
- Issue creation for detected drift
- Slack notifications (if configured)
- Drift plan artifacts for investigation

**Steps**:
1. Run Terraform plan in drift-detection mode
2. Compare current state with expected state
3. Create GitHub issues for detected drift
4. Send notifications
5. Upload drift plans as artifacts

## Required Secrets

### Azure Authentication
- `ARM_CLIENT_ID` - Service principal client ID
- `ARM_CLIENT_SECRET` - Service principal client secret
- `ARM_SUBSCRIPTION_ID` - Azure subscription ID
- `ARM_TENANT_ID` - Azure tenant ID
- `AZURE_CREDENTIALS` - Complete Azure credentials JSON

### Optional Secrets
- `INFRACOST_API_KEY` - For cost estimation (get from infracost.io)
- `SLACK_WEBHOOK_URL` - For Slack notifications

## Environment Setup

### GitHub Environments

Create the following environments in your GitHub repository:

1. **dev** - No protection rules, auto-deploys
2. **staging** - Requires manual approval
3. **prod** - Requires manual approval, restricted to main branch

### Environment Protection Rules

For staging and prod environments:

1. Go to repository Settings > Environments
2. Select the environment
3. Configure protection rules:
   - **Required reviewers**: Add team members
   - **Wait timer**: Optional delay before deployment
   - **Deployment branches**: Restrict to main branch only

## Usage Examples

### Creating Infrastructure Changes

1. **Create feature branch**:
   ```bash
   git checkout -b feature/add-monitoring
   ```

2. **Make changes** to Terraform files

3. **Commit and push**:
   ```bash
   git add .
   git commit -m "Add monitoring configuration"
   git push origin feature/add-monitoring
   ```

4. **Create pull request** - This triggers the plan workflow

5. **Review results** in PR comments

6. **Merge after approval** - This triggers deployment

### Manual Deployment

Use workflow dispatch for manual deployments:

1. Go to Actions tab in GitHub
2. Select "Terraform Deploy" workflow
3. Click "Run workflow"
4. Select environment and action (apply/destroy)
5. Confirm and run

### Handling Drift

When drift is detected:

1. Review the created GitHub issue
2. Download drift plan artifacts
3. Investigate the cause:
   - Manual changes in Azure portal
   - External automation
   - Configuration errors

4. Take corrective action:
   - Update Terraform code to match current state, or
   - Apply Terraform to restore expected state

5. Close the issue once resolved

## Security Features

### Code Scanning

**Checkov**: Infrastructure security scanning
- Scans for security misconfigurations
- Checks compliance with best practices
- Results uploaded to GitHub Security tab

**TFSec**: Terraform-specific security scanning
- Static analysis of Terraform code
- Identifies potential security issues
- Integrates with GitHub Advanced Security

### Access Control

**Service Principals**: Dedicated service principals for automation
- Minimal required permissions
- Separate principals for different purposes
- Regular credential rotation

**Environment Protection**: Manual approvals for production
- Required reviewers for sensitive environments
- Audit trail of all deployments
- Branch restrictions

## Monitoring and Alerting

### Workflow Monitoring

Monitor workflow health:
- Check workflow run history
- Review failure notifications
- Monitor resource usage

### Cost Monitoring

Track infrastructure costs:
- Infracost estimates in PR comments
- Regular cost reviews
- Budget alerts in Azure

### Drift Monitoring

Stay informed about configuration changes:
- Daily drift detection
- Automatic issue creation
- Slack notifications for immediate awareness

## Troubleshooting

### Common Issues

**Authentication Failures**:
- Verify service principal credentials
- Check secret expiration dates
- Ensure proper permissions

**Terraform State Locks**:
- Check for stuck operations
- Manually release locks if needed
- Investigate concurrent operations

**Plan Failures**:
- Review Terraform validation errors
- Check resource dependencies
- Verify Azure resource limits

**Deployment Timeouts**:
- Increase workflow timeout values
- Check Azure resource provisioning times
- Review resource dependencies

### Debugging Steps

1. **Check workflow logs** in GitHub Actions
2. **Review Terraform output** for specific errors
3. **Verify Azure resources** in the portal
4. **Check service principal permissions**
5. **Validate configuration files**

## Best Practices

### Development Workflow

1. **Always use pull requests** for infrastructure changes
2. **Review plan outputs** before merging
3. **Test in dev environment** first
4. **Use conventional commit messages** (automatically validated)
5. **Keep changes small and focused**

### Conventional Commits

All commit messages must follow the [Conventional Commits](https://www.conventionalcommits.org/) specification:

**Format**: `<type>[optional scope]: <description>`

**Valid Types**:
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation changes
- `ci`: CI/CD changes
- `chore`: Maintenance tasks
- `refactor`: Code refactoring
- `test`: Test changes

**Examples**:
- `feat(aks): add GPU node pool support`
- `fix(monitoring): resolve Grafana ingress issue`
- `docs: update deployment guide`
- `ci: add conventional commit validation`

### Security Practices

1. **Rotate secrets regularly** (quarterly recommended)
2. **Use least privilege** for service principals
3. **Monitor security scan results**
4. **Keep Terraform providers updated**
5. **Review access permissions regularly**

### Operational Practices

1. **Monitor drift detection** results
2. **Review cost estimates** for budget impact
3. **Maintain environment parity**
4. **Document infrastructure changes**
5. **Plan for disaster recovery**

## Advanced Configuration

### Custom Workflows

Extend the pipelines for specific needs:
- Add custom validation steps
- Integrate with external tools
- Implement custom notification logic
- Add compliance checks

### Multi-Region Deployment

Adapt workflows for multi-region:
- Matrix strategy for regions
- Region-specific configurations
- Cross-region dependencies
- Disaster recovery automation

### Integration with External Tools

Connect with other systems:
- ServiceNow for change management
- Jira for issue tracking
- PagerDuty for alerting
- Datadog for monitoring
