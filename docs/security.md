# Security Guide

This guide covers security best practices and configurations implemented in the Azure AKS GitOps platform.

## Security Framework

The platform implements a **defense-in-depth** security strategy across multiple layers:

1. **Identity and Access Management**
2. **Network Security**
3. **Data Protection**
4. **Application Security**
5. **Infrastructure Security**
6. **Compliance and Governance**

## Identity and Access Management

### **Azure Active Directory Integration**

#### **Service Principals**
```bash
# Dedicated service principals for different purposes
├── terraform-sp (Infrastructure management)
├── aks-sp (Cluster operations)
├── monitoring-sp (Observability)
└── backup-sp (Data protection)
```

**Security Features**:
- Minimal required permissions (least privilege)
- Regular credential rotation (quarterly)
- Separate principals for different environments
- Audit logging for all operations

#### **RBAC Configuration**
```yaml
# Kubernetes RBAC example
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: developer-role
rules:
- apiGroups: ["apps"]
  resources: ["deployments", "replicasets"]
  verbs: ["get", "list", "create", "update"]
```

### **ArgoCD Security**

#### **OIDC Integration**
```yaml
# ArgoCD OIDC configuration
oidc.config: |
  name: Azure AD
  issuer: https://login.microsoftonline.com/TENANT_ID/v2.0
  clientId: CLIENT_ID
  requestedScopes: ["openid", "profile", "email", "groups"]
```

#### **RBAC Policies**
```csv
# ArgoCD RBAC policy
p, role:admin, applications, *, */*, allow
p, role:developer, applications, get, */*, allow
p, role:developer, applications, sync, dev/*, allow
g, azure-ad-group:developers, role:developer
```

## Network Security

### **Network Segmentation**

#### **Virtual Network Design**
```
VNet (10.0.0.0/16)
├── AKS Subnet (10.0.1.0/24)
│   └── Network Security Group (AKS-NSG)
├── App Gateway Subnet (10.0.2.0/24)
│   └── Network Security Group (AppGW-NSG)
└── Private Endpoints Subnet (10.0.3.0/24)
    └── Network Security Group (PE-NSG)
```

#### **Network Security Groups**
```hcl
# Example NSG rule
resource "azurerm_network_security_rule" "allow_https" {
  name                       = "AllowHTTPS"
  priority                   = 1001
  direction                  = "Inbound"
  access                     = "Allow"
  protocol                   = "Tcp"
  source_port_range          = "*"
  destination_port_range     = "443"
  source_address_prefix      = "Internet"
  destination_address_prefix = "*"
}
```

### **Private Endpoints**

All Azure services use private endpoints for secure connectivity:

- **Container Registry**: Private endpoint with DNS integration
- **Key Vault**: Private endpoint for secret access
- **Storage Accounts**: Private endpoint for Terraform state
- **Database Services**: Private endpoint for MLflow backend

### **Application Gateway WAF**

#### **Web Application Firewall Rules**
```hcl
resource "azurerm_web_application_firewall_policy" "main" {
  name                = "${var.project_name}-waf-policy"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  policy_settings {
    enabled                     = true
    mode                       = "Prevention"
    request_body_check         = true
    file_upload_limit_in_mb    = 100
    max_request_body_size_in_kb = 128
  }

  managed_rules {
    managed_rule_set {
      type    = "OWASP"
      version = "3.2"
    }
  }
}
```

## Data Protection

### **Encryption at Rest**

#### **Azure Disk Encryption**
```hcl
resource "azurerm_kubernetes_cluster" "main" {
  disk_encryption_set_id = azurerm_disk_encryption_set.main.id
  
  default_node_pool {
    os_disk_type = "Managed"
    os_disk_size_gb = 100
  }
}
```

#### **Storage Account Encryption**
```hcl
resource "azurerm_storage_account" "terraform_state" {
  encryption {
    services {
      blob {
        enabled = true
      }
      file {
        enabled = true
      }
    }
    key_source = "Microsoft.Storage"
  }
}
```

### **Encryption in Transit**

- **TLS 1.2+** for all external communications
- **mTLS** for service-to-service communication (optional with service mesh)
- **HTTPS** enforced on all ingress endpoints
- **Encrypted** Kubernetes API server communication

### **Secret Management**

#### **Azure Key Vault Integration**
```yaml
# CSI Secret Store driver configuration
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: app-secrets
spec:
  provider: azure
  parameters:
    usePodIdentity: "false"
    useVMManagedIdentity: "true"
    userAssignedIdentityID: "CLIENT_ID"
    keyvaultName: "your-keyvault"
    objects: |
      array:
        - |
          objectName: database-password
          objectType: secret
```

#### **Secret Rotation**
```bash
# Automated secret rotation script
#!/bin/bash
# Rotate service principal secrets quarterly
az ad sp credential reset --id $SP_ID --years 1
kubectl create secret generic sp-secret --from-literal=client-secret=$NEW_SECRET
```

## Application Security

### **Container Security**

#### **Image Scanning**
```yaml
# GitHub Actions security scanning
- name: Run Trivy vulnerability scanner
  uses: aquasecurity/trivy-action@master
  with:
    image-ref: 'myregistry.azurecr.io/myapp:${{ github.sha }}'
    format: 'sarif'
    output: 'trivy-results.sarif'
```

#### **Security Contexts**
```yaml
# Pod security context
apiVersion: v1
kind: Pod
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
    fsGroup: 2000
  containers:
  - name: app
    securityContext:
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true
      capabilities:
        drop:
        - ALL
```

### **Network Policies**

#### **Kubernetes Network Policies**
```yaml
# Deny all ingress traffic by default
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-ingress
spec:
  podSelector: {}
  policyTypes:
  - Ingress
---
# Allow specific traffic
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-frontend-to-backend
spec:
  podSelector:
    matchLabels:
      app: backend
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: frontend
    ports:
    - protocol: TCP
      port: 8080
```

### **Pod Security Standards**

#### **Pod Security Policy (Deprecated) / Pod Security Standards**
```yaml
# Pod Security Standards enforcement
apiVersion: v1
kind: Namespace
metadata:
  name: secure-namespace
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
```

## Infrastructure Security

### **AKS Security Features**

#### **Private Cluster**
```hcl
resource "azurerm_kubernetes_cluster" "main" {
  private_cluster_enabled = true
  
  api_server_access_profile {
    authorized_ip_ranges = var.authorized_ip_ranges
  }
  
  network_profile {
    network_plugin = "azure"
    network_policy = "calico"
  }
}
```

#### **Azure Policy Integration**
```hcl
resource "azurerm_kubernetes_cluster" "main" {
  azure_policy_enabled = true
  
  oms_agent {
    enabled                    = true
    log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  }
}
```

### **Terraform Security**

#### **State File Security**
```hcl
# Secure Terraform backend
terraform {
  backend "azurerm" {
    storage_account_name = "tfstate"
    container_name       = "tfstate"
    key                  = "terraform.tfstate"
    
    # Enable encryption
    use_azuread_auth = true
  }
}
```

#### **Security Scanning**
```yaml
# Checkov security scanning in CI/CD
- name: Run Checkov
  uses: bridgecrewio/checkov-action@master
  with:
    directory: terraform
    framework: terraform
    output_format: sarif
```

## Compliance and Governance

### **Audit Logging**

#### **Azure Activity Logs**
```hcl
resource "azurerm_monitor_diagnostic_setting" "main" {
  name               = "audit-logs"
  target_resource_id = data.azurerm_subscription.current.id
  
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  
  enabled_log {
    category = "Administrative"
  }
  
  enabled_log {
    category = "Security"
  }
}
```

#### **Kubernetes Audit Logs**
```yaml
# AKS audit log configuration
apiVersion: audit.k8s.io/v1
kind: Policy
rules:
- level: Metadata
  namespaces: ["kube-system", "kube-public", "kube-node-lease"]
  verbs: ["get", "list", "watch"]
  omitStages:
  - RequestReceived
```

### **Compliance Frameworks**

#### **CIS Benchmarks**
- CIS Kubernetes Benchmark compliance
- CIS Azure Foundations Benchmark
- Automated compliance checking with Checkov

#### **SOC 2 / ISO 27001 Readiness**
- Comprehensive audit logging
- Access control documentation
- Incident response procedures
- Data classification and handling

## Security Monitoring

### **Security Information and Event Management (SIEM)**

#### **Azure Sentinel Integration**
```hcl
resource "azurerm_sentinel_data_connector_azure_active_directory" "main" {
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  tenant_id                  = data.azurerm_client_config.current.tenant_id
}
```

#### **Security Alerts**
```yaml
# Prometheus alerting rules for security
groups:
- name: security.rules
  rules:
  - alert: UnauthorizedAPIAccess
    expr: increase(apiserver_audit_total{verb="create",objectRef_resource="secrets"}[5m]) > 0
    for: 0m
    labels:
      severity: critical
    annotations:
      summary: "Unauthorized secret access detected"
```

### **Vulnerability Management**

#### **Container Image Scanning**
```bash
# Automated vulnerability scanning
az acr task create \
  --registry myregistry \
  --name security-scan \
  --image myapp:{{.Run.ID}} \
  --context https://github.com/myorg/myapp.git \
  --file Dockerfile \
  --commit-trigger-enabled true
```

## Incident Response

### **Security Incident Playbook**

#### **Detection and Analysis**
1. **Monitor security alerts** in Azure Security Center
2. **Review audit logs** for suspicious activity
3. **Analyze network traffic** patterns
4. **Check for unauthorized access** attempts

#### **Containment and Eradication**
1. **Isolate affected resources** using network policies
2. **Rotate compromised credentials** immediately
3. **Apply security patches** to affected systems
4. **Update security rules** to prevent recurrence

#### **Recovery and Lessons Learned**
1. **Restore services** from clean backups
2. **Verify system integrity** before resuming operations
3. **Document incident details** for future reference
4. **Update security procedures** based on findings

## Security Best Practices

### **Development Security**
- **Secure coding practices** and code reviews
- **Dependency scanning** for known vulnerabilities
- **Static application security testing** (SAST)
- **Dynamic application security testing** (DAST)

### **Operational Security**
- **Regular security assessments** and penetration testing
- **Security awareness training** for team members
- **Incident response drills** and tabletop exercises
- **Continuous security monitoring** and alerting

### **Data Security**
- **Data classification** and handling procedures
- **Privacy by design** principles
- **Data retention policies** and secure deletion
- **Cross-border data transfer** compliance

This comprehensive security framework ensures the platform meets enterprise security requirements while maintaining operational efficiency.
