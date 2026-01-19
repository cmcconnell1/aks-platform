# Azure Cost Monitoring Guide

This guide explains how to monitor Azure costs for infrastructure deployed by the Azure AKS GitOps platform project using the unified cost monitoring solution.

## Overview

The platform provides a **unified cost monitoring solution** that combines multiple capabilities in a single, easy-to-use tool:

1. **Cost Estimation** - Planning costs using Azure pricing data
2. **Real-time Cost Monitoring** - Track actual Azure billing costs
3. **Budget Alerts** - Automated notifications when costs exceed thresholds
4. **Cost Dashboards** - Visual cost monitoring with auto-refresh
5. **Scheduled Monitoring** - Automated daily/weekly/monthly cost reports

## Unified Cost Monitoring Tool

### Primary Tool: `cost-monitor.sh`
**File**: `scripts/cost-monitor.sh`

Single unified tool that handles all cost monitoring needs through different modes:

**Key Features**:
- **Three modes**: Estimation, actual billing, and dashboard generation
- **Simplified interface**: One command for all cost monitoring needs
- **Flexible dependencies**: Works with or without Azure CLI/Python depending on mode
- **Automated scheduling**: Cron job setup for regular monitoring
- **Budget alerts**: Threshold monitoring with webhook notifications
- **Multi-environment support**: Dev, staging, production cost tracking

### Supporting Tools

#### Core API Integration: `azure-cost-monitor.py`
**File**: `scripts/azure-cost-monitor.py`
- Core Python utility for Azure Cost Management API integration
- Used internally by cost-monitor.sh for actual billing data
- Can be used directly for advanced scenarios

#### Dashboard Visualization: `cost-dashboard.sh`
**File**: `scripts/cost-dashboard.sh`
- HTML dashboard generation with auto-refresh
- Used by cost-monitor.sh in dashboard mode
- Can be used independently for dashboard-only scenarios

## Quick Start

### Prerequisites

1. **Azure CLI Authentication**:
```bash
az login
az account set --subscription "your-subscription-id"
```

2. **Python Dependencies**:
```bash
pip install azure-mgmt-costmanagement azure-identity azure-mgmt-resource requests
```

3. **Optional Tools**:
```bash
# For dashboard features
sudo apt-get install jq  # Linux
brew install jq          # macOS
```

### Basic Usage

#### Cost Estimation (No Azure CLI Required)
```bash
# Quick cost estimates for planning
./scripts/cost-monitor.sh --estimate --env dev

# Estimates with regional pricing
./scripts/cost-monitor.sh --estimate --env prod --region westus2
```

#### Actual Cost Monitoring (Requires Azure CLI)
```bash
# Current month actual costs
# Uses default project name: aks-platform
./scripts/cost-monitor.sh --actual

# Or with custom project name
./scripts/cost-monitor.sh --actual --project-name "acme-platform"

# Environment-specific costs with budget alerts
./scripts/cost-monitor.sh --actual --env prod --budget 1000
```

#### Cost Dashboard
```bash
# Generate static HTML dashboard
./scripts/cost-monitor.sh --dashboard --output costs.html

# Serve live dashboard with auto-refresh
./scripts/cost-monitor.sh --dashboard --serve --port 8080 --budget 1000
```

#### Unified Commands (Default: Actual Costs)
```bash
# Simple cost check (defaults to --actual mode, uses default project: aks-platform)
./scripts/cost-monitor.sh

# With Slack notifications
./scripts/cost-monitor.sh --budget 1000 \
  --webhook "https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK"
```

## Advanced Usage

### Scheduled Monitoring

Set up automated cost monitoring with cron jobs:

```bash
# Daily monitoring at 9 AM with budget alerts
./scripts/cost-monitor.sh --schedule daily \
  --budget 1000 --webhook "https://hooks.slack.com/services/..."

# Weekly monitoring every Monday
./scripts/cost-monitor.sh --schedule weekly \
  --budget 5000
```

This creates cron jobs that automatically:
- Monitor costs at specified intervals
- Send notifications when budgets are exceeded
- Track cost trends over time
- Generate reports for stakeholders

### Cost Analysis and Reporting

#### Detailed Cost Analysis
```bash
# Last 30 days with export (uses default project: aks-platform)
python3 scripts/azure-cost-monitor.py \
  --days 30 --export monthly-costs.json

# Production environment only
python3 scripts/azure-cost-monitor.py \
  --environment prod --budget-alert 2000
```

#### Quiet Mode for Scripting
```bash
# Get just the total cost (for scripts)
COST=$(./scripts/cost-monitor.sh --quiet)
echo "Current cost: $COST USD"

# Export data for external processing
./scripts/cost-monitor.sh \
  --export /var/log/azure-costs.json --quiet
```

### Integration with Monitoring Systems

#### Prometheus Integration
```bash
# Create metrics endpoint
echo "azure_cost_total $COST" > /var/lib/prometheus/node-exporter/azure-costs.prom
```

#### Grafana Dashboard
The exported JSON data can be imported into Grafana for advanced visualization and alerting.

#### Log Aggregation
```bash
# Send costs to syslog
COST=$(./scripts/cost-monitor.sh --quiet)
logger "Azure costs: $COST USD for project aks-platform"
```

## Budget Management

### Setting Up Budget Alerts

Budget alerts are triggered at different thresholds:

- **75% of budget**: Caution alert (yellow)
- **90% of budget**: Warning alert (orange)
- **100%+ of budget**: Critical alert (red)

```bash
# Set monthly budget of $1000
./scripts/cost-monitor.sh --budget 1000

# Environment-specific budgets
./scripts/cost-monitor.sh --env prod --budget 2000
./scripts/cost-monitor.sh --env staging --budget 500
./scripts/cost-monitor.sh --env dev --budget 300
```

### Notification Webhooks

#### Slack Integration
```bash
# Create Slack webhook in your workspace
# Use webhook URL with cost monitor
./scripts/cost-monitor.sh --webhook "https://hooks.slack.com/services/YOUR_WORKSPACE/YOUR_CHANNEL/YOUR_TOKEN"
```

#### Microsoft Teams Integration
```bash
# Create Teams webhook connector
# Use webhook URL with cost monitor
./scripts/cost-monitor.sh --webhook "https://outlook.office.com/webhook/..."
```

#### Custom Webhook Format
The webhook receives JSON payload:
```json
{
  "attachments": [
    {
      "color": "danger",
      "title": "Azure Cost Alert - aks-platform",
      "text": "CRITICAL: Azure costs have exceeded budget limit",
      "footer": "Azure Cost Monitor",
      "ts": 1640995200
    }
  ]
}
```

## Cost Optimization

### Identifying Cost Drivers

Use the cost breakdown to identify the most expensive resources:

```bash
# Detailed breakdown by resource group
python3 scripts/azure-cost-monitor.py --days 30
```

Common cost drivers in AKS environments:
- **Compute**: Node pools, especially GPU-enabled nodes
- **Storage**: Premium SSD, backup storage
- **Networking**: Application Gateway for Containers (AGC), Load Balancer data transfer
- **Monitoring**: Log Analytics data ingestion and retention

### Cost Reduction Strategies

1. **Right-size Node Pools**: Monitor CPU/memory utilization
2. **Use Spot Instances**: For non-critical workloads
3. **Optimize Storage**: Use appropriate storage tiers
4. **Review Retention Policies**: Logs, backups, and monitoring data
5. **Schedule Resources**: Shut down dev/test environments after hours

## Troubleshooting

### Common Issues

#### Authentication Errors
```bash
# Ensure Azure CLI is authenticated
az login
az account show

# Check subscription access
az account list --output table
```

#### Permission Errors
```bash
# Verify Cost Management permissions
az role assignment list --assignee $(az account show --query user.name -o tsv) \
  --query "[?roleDefinitionName=='Cost Management Reader']"
```

#### Missing Cost Data
- Cost data may have 24-48 hour delay
- Ensure resources are properly tagged
- Check if resource groups follow naming conventions

#### Python Package Errors
```bash
# Install/upgrade required packages
pip install --upgrade azure-mgmt-costmanagement azure-identity azure-mgmt-resource
```

### Debugging

Enable verbose output for troubleshooting:

```bash
# Debug mode
python3 scripts/azure-cost-monitor.py --debug

# Check resource group discovery
az group list --query "[?contains(name, 'aks-platform')].name" --output table
```

## Best Practices

### Regular Monitoring
- Set up daily monitoring for production environments
- Weekly monitoring for staging environments
- Monthly monitoring for development environments

### Budget Planning
- Set realistic budgets based on historical data
- Include buffer for unexpected costs (20-30%)
- Review and adjust budgets quarterly

### Cost Governance
- Tag all resources with project and environment labels
- Implement approval workflows for expensive resources
- Regular cost reviews with stakeholders

### Automation
- Use scheduled monitoring to catch cost spikes early
- Integrate with existing monitoring and alerting systems
- Automate cost reports for management

## Integration Examples

### CI/CD Pipeline Integration
```yaml
# GitHub Actions workflow
- name: Check Azure Costs
  run: |
    COST=$(./scripts/cost-monitor.sh --quiet --project-name "${{ env.PROJECT_NAME }}")
    if (( $(echo "$COST > 1000" | bc -l) )); then
      echo "::warning::High Azure costs detected: $COST USD"
    fi
```

### Monitoring System Integration
```bash
# Nagios/Icinga check
#!/bin/bash
COST=$(./scripts/cost-monitor.sh --quiet)
if (( $(echo "$COST > 1000" | bc -l) )); then
  echo "CRITICAL - Azure costs: $COST USD"
  exit 2
fi
echo "OK - Azure costs: $COST USD"
exit 0
```

## Future Cost Considerations

The following optional components are not currently implemented but may be added in the future. Consider these costs when planning:

### Azure Front Door (Optional - Not Implemented)

| Tier | Base Cost | Additional Costs | Use Case |
|------|-----------|------------------|----------|
| **Standard** | ~$35/month | + ~$0.01/10K requests | Basic global routing, SSL, caching |
| **Premium** | ~$330/month | + requests + WAF rules | Production with WAF, Private Link |

**When to consider**: Global users, WAF requirements, multi-region HA, edge caching needs.

See [Architecture Guide - Azure Front Door](./architecture.md#azure-front-door-future-option) for detailed feature comparison and trade-offs.

### Service Mesh - Istio (Optional)

| Cost Type | Impact | Notes |
|-----------|--------|-------|
| **Sidecar Overhead** | +10-15% CPU/memory per pod | Every pod gets Envoy proxy |
| **Control Plane** | ~2 vCPU, 4GB RAM | istiod, always running |
| **Additional Latency** | ~1-3ms per hop | Proxy overhead |

**When worth the cost**: Zero-trust security requirements, complex traffic routing (canary, A/B), microservices with 10+ services.

### Azure Arc (Optional)

| Component | Cost | Notes |
|-----------|------|-------|
| **Control Plane** | Free | Arc agent and basic management |
| **GitOps (Flux)** | Free - $2/cluster/month | Basic vs advanced features |
| **Azure Policy** | Free | Included with Arc |
| **Azure Monitor** | Standard LA pricing | ~$2.30/GB ingested |
| **Arc Data Services** | Per-vCore pricing | If using Arc-enabled SQL/PostgreSQL |

**When worth the cost**: Managing on-premises or multi-cloud Kubernetes clusters alongside AKS.

### Kubeflow (Optional)

| Component | Estimated Monthly Cost | Notes |
|-----------|----------------------|-------|
| **Control Plane** | $100-200 | Always-on pods (pipelines, UI, etc.) |
| **Pipeline Execution** | Variable | Compute during pipeline runs |
| **Model Serving (KServe)** | $50-500+ | Depends on inference load |
| **Storage** | $20-100 | Artifacts, models, metadata |

**Total estimated**: $200-500/month base + GPU/compute usage

**When worth the cost**: Complex ML pipelines, distributed training, model serving at scale, dedicated ML platform team.

### Multi-Region Deployment (Optional)

| Component | Cost Multiplier | Notes |
|-----------|-----------------|-------|
| **AKS Clusters** | 2x | Duplicate cluster per region |
| **Networking** | 2x | VNets, AGC, private endpoints |
| **Data Replication** | +20-40% | Cross-region egress, geo-redundant storage |
| **Front Door** | +$35-330/month | Required for global routing |
| **Monitoring** | +50% | Additional region's telemetry |

**Total estimated**: 80-120% increase over single-region

**When worth the cost**: < 4hr RTO requirements, global user base, regulatory data residency, 99.99%+ SLA needs.

### Cost Planning for Scale

When scaling the platform, consider these cost multipliers:

| Scale Factor | Impact | Mitigation |
|--------------|--------|------------|
| Multi-region | 2-3x base infrastructure | Use active-passive for DR |
| GPU workloads | $1-5/hour per GPU | Scale to zero when idle |
| Front Door Premium | +$330/month base | Start with Standard tier |
| Increased traffic | Per-request charges | Implement caching strategies |

This comprehensive cost monitoring solution provides complete visibility into Azure spending, enabling proactive cost management and budget control for the AKS GitOps platform.
