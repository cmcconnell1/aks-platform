# Application Gateway for Containers (AGC) Guide

This guide explains the Application Gateway for Containers (AGC) implementation in the AKS platform, providing cloud-native load balancing and traffic management for container workloads.

## Table of Contents

1. [Overview](#overview)
2. [Why AGC](#why-agc)
3. [Architecture](#architecture)
4. [Components](#components)
5. [Configuration](#configuration)
6. [Routing with Gateway API](#routing-with-gateway-api)
7. [TLS/SSL Configuration](#tlsssl-configuration)
8. [Troubleshooting](#troubleshooting)
9. [Migration from AGIC](#migration-from-agic)

## Overview

Application Gateway for Containers (AGC) is a next-generation application load balancing solution designed specifically for containerized workloads on Azure Kubernetes Service. It provides:

- Cloud-native traffic management
- Sub-second configuration updates
- Native Gateway API support
- Elastic scaling
- Enhanced observability

### Key Concepts

| Term | Description |
|------|-------------|
| **AGC** | Application Gateway for Containers - the managed load balancer service |
| **ALB Controller** | Azure Load Balancer Controller - Kubernetes controller managing AGC |
| **Gateway API** | Kubernetes-native API for configuring traffic routing |
| **Frontend** | Entry point for external traffic |
| **Association** | Links AGC to a subnet in your VNet |

## Why AGC

### Comparison with Previous Approaches

| Feature | AGIC (Legacy) | AGC (Current) |
|---------|---------------|---------------|
| Configuration Speed | 30-60 seconds | ~5 seconds |
| API Model | Ingress only | Gateway API + Ingress |
| Scalability | Limited backends | Thousands of backends |
| Architecture | Controller updates AppGw | Cloud-native dataplane |
| Backend Protocol | HTTP/HTTPS | HTTP/HTTPS + gRPC |
| Traffic Splitting | Limited | Native support |
| Custom Health Probes | Via annotations | Full Gateway API support |
| Cost Model | Fixed SKU | Pay-per-use |

### Benefits

1. **Faster Configuration**: Updates propagate in ~5 seconds vs 30-60 seconds with AGIC
2. **Gateway API Support**: Uses Kubernetes-native Gateway API standard
3. **Elastic Scaling**: Automatically scales based on traffic
4. **Enhanced Traffic Control**: Native support for canary deployments, traffic splitting
5. **Better Observability**: Rich metrics and logs integration
6. **Cost Efficiency**: Pay-per-use pricing model

## Architecture

```
+------------------+     +-------------------+     +------------------+
|  External        |     |    Azure          |     |  AKS Cluster     |
|  Traffic         |     |    AGC            |     |                  |
+------------------+     +-------------------+     +------------------+
        |                        |                        |
        | 1. HTTPS request       |                        |
        +----------------------->|                        |
                                 |                        |
                   +-------------+-------------+          |
                   |         Frontend          |          |
                   |   (Public IP/FQDN)        |          |
                   +-------------+-------------+          |
                                 |                        |
                                 | 2. Route based on      |
                                 |    Gateway/HTTPRoute   |
                                 |                        |
                   +-------------+-------------+          |
                   |         Association       |          |
                   |   (VNet Subnet Link)      |          |
                   +-------------+-------------+          |
                                 |                        |
                                 | 3. Forward to          |
                                 |    backend pods        |
                                 +----------------------->|
                                                          |
                                               +----------+-----------+
                                               |   ALB Controller     |
                                               |   (manages config)   |
                                               +----------+-----------+
                                                          |
                                               +----------+-----------+
                                               |   Application Pods   |
                                               +----------------------+
```

## Components

### AGC Module Structure

The AGC implementation in this project consists of:

```
terraform/modules/agc/
├── main.tf           # AGC resources, ALB Controller, Gateway
├── variables.tf      # Configuration variables
└── outputs.tf        # Module outputs
```

### Key Resources

1. **Application Gateway for Containers** (`azurerm_application_gateway_for_containers`)
   - The main AGC resource in Azure

2. **Frontend** (`azurerm_application_gateway_for_containers_frontend`)
   - Provides external-facing IP/FQDN

3. **Association** (`azurerm_application_gateway_for_containers_association`)
   - Links AGC to the AGC subnet with delegation

4. **ALB Controller** (Helm release)
   - Kubernetes controller that manages AGC configuration

5. **Gateway API CRDs** (Helm release)
   - Custom Resource Definitions for Gateway API

## Configuration

### Terraform Variables

```hcl
# Enable AGC
enable_agc = true

# Create default Gateway resource
create_default_gateway = true

# Enable HTTPS
enable_agc_https = true

# ALB Controller version
alb_controller_version = "1.3.7"

# Gateway API version
gateway_api_version = "1.2.0"

# Subnet for AGC (requires delegation)
agc_subnet_address_prefix = "10.0.2.0/24"
```

### Subnet Requirements

AGC requires a dedicated subnet with delegation to `Microsoft.ServiceNetworking/trafficControllers`:

```hcl
resource "azurerm_subnet" "agc" {
  name                 = "agc-subnet"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.2.0/24"]

  delegation {
    name = "agc-delegation"
    service_delegation {
      name = "Microsoft.ServiceNetworking/trafficControllers"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}
```

## Routing with Gateway API

### Gateway Resource

The Gateway resource defines listeners for incoming traffic:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: aks-platform-gateway
  namespace: default
  annotations:
    alb.networking.azure.io/alb-id: <AGC_RESOURCE_ID>
spec:
  gatewayClassName: azure-alb-external
  listeners:
    - name: http
      port: 80
      protocol: HTTP
    - name: https
      port: 443
      protocol: HTTPS
      tls:
        mode: Terminate
        certificateRefs:
          - name: tls-secret
  addresses:
    - type: alb.networking.azure.io/alb-frontend
      value: <FRONTEND_ID>
```

### HTTPRoute Resource

HTTPRoute defines how traffic is routed to backends:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: grafana
  namespace: monitoring
spec:
  parentRefs:
    - name: aks-platform-gateway
      namespace: default
  hostnames:
    - grafana.example.com
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - name: prometheus-grafana
          port: 80
```

### Traffic Splitting (Canary Deployments)

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: app-canary
spec:
  parentRefs:
    - name: aks-platform-gateway
  rules:
    - backendRefs:
        - name: app-stable
          port: 80
          weight: 90
        - name: app-canary
          port: 80
          weight: 10
```

## TLS/SSL Configuration

### Using cert-manager with AGC

1. **Create a ClusterIssuer** (configured automatically):
   ```yaml
   apiVersion: cert-manager.io/v1
   kind: ClusterIssuer
   metadata:
     name: letsencrypt-prod
   spec:
     acme:
       server: https://acme-v02.api.letsencrypt.org/directory
       email: admin@example.com
       privateKeySecretRef:
         name: letsencrypt-prod
       solvers:
         - http01:
             ingress:
               ingressClassName: azure-alb-external
   ```

2. **Create a Certificate**:
   ```yaml
   apiVersion: cert-manager.io/v1
   kind: Certificate
   metadata:
     name: app-tls
     namespace: default
   spec:
     secretName: app-tls-secret
     issuerRef:
       name: letsencrypt-prod
       kind: ClusterIssuer
     dnsNames:
       - app.example.com
   ```

3. **Reference in Gateway**:
   ```yaml
   spec:
     listeners:
       - name: https
         port: 443
         protocol: HTTPS
         tls:
           certificateRefs:
             - name: app-tls-secret
   ```

## Troubleshooting

### Common Issues

#### 1. ALB Controller Not Running

**Symptoms:**
- Gateway resources stuck in pending
- No routes being created

**Solutions:**
```bash
# Check ALB Controller pods
kubectl get pods -n azure-alb-system

# Check ALB Controller logs
kubectl logs -n azure-alb-system -l app=alb-controller

# Verify workload identity
kubectl get sa -n azure-alb-system alb-controller-sa -o yaml
```

#### 2. Gateway Not Programmed

**Symptoms:**
- Gateway status shows "Not Programmed"
- HTTPRoutes not working

**Solutions:**
```bash
# Check Gateway status
kubectl get gateway -A -o wide

# Describe Gateway for events
kubectl describe gateway <gateway-name>

# Verify AGC association
az network application-gateway-for-containers association list \
  --resource-group <rg-name> \
  --alb-name <agc-name>
```

#### 3. HTTPRoute Not Routing

**Symptoms:**
- Requests returning 404
- Traffic not reaching backend

**Solutions:**
```bash
# Check HTTPRoute status
kubectl get httproute -A

# Verify backend service exists
kubectl get svc -n <namespace>

# Check HTTPRoute references correct Gateway
kubectl describe httproute <route-name>
```

### Debugging Commands

```bash
# Get AGC frontend FQDN
terraform output agc_frontend_fqdn

# Check all Gateway API resources
kubectl get gateways,httproutes,referencegrants -A

# View ALB Controller configuration
kubectl get configmap -n azure-alb-system alb-controller-config -o yaml

# Check workload identity tokens
kubectl exec -n azure-alb-system <pod-name> -- \
  cat /var/run/secrets/azure/tokens/azure-identity-token | jwt decode -
```

## Migration from AGIC

If migrating from Application Gateway with AGIC to AGC:

### Step 1: Deploy AGC Alongside AGIC

AGC can coexist with AGIC during migration:

```hcl
# Keep both enabled temporarily
enable_agc = true
# AGIC will be removed after AGC is validated
```

### Step 2: Update DNS

Update DNS to point to the new AGC frontend FQDN:

```bash
# Get new FQDN
terraform output agc_frontend_fqdn

# Update DNS CNAME records to point to this FQDN
```

### Step 3: Migrate Ingress Resources

Convert Ingress resources to HTTPRoute:

**Before (Ingress):**
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: grafana
  annotations:
    kubernetes.io/ingress.class: azure/application-gateway
spec:
  rules:
    - host: grafana.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: grafana
                port:
                  number: 80
```

**After (HTTPRoute):**
```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: grafana
spec:
  parentRefs:
    - name: aks-platform-gateway
  hostnames:
    - grafana.example.com
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - name: grafana
          port: 80
```

### Step 4: Remove AGIC

After validating AGC is working:

```hcl
# Disable legacy Application Gateway
# (This project has already migrated to AGC-only)
```

## Related Documentation

- [Azure AGC Documentation](https://learn.microsoft.com/en-us/azure/application-gateway/for-containers/overview)
- [Gateway API Specification](https://gateway-api.sigs.k8s.io/)
- [ALB Controller Documentation](https://learn.microsoft.com/en-us/azure/application-gateway/for-containers/alb-controller)
- [Deployment Guide](./deployment-guide.md)
- [Troubleshooting Guide](./troubleshooting.md)
