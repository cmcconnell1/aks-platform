# Architecture Guide

This guide explains the system architecture and design decisions for the Azure AKS GitOps platform.

## High-Level Architecture

```mermaid
graph TB
    Internet[Internet]

    DevAppGW[Dev - Application Gateway]
    DevAKS[Dev - AKS Cluster]
    DevACR[Dev - Container Registry]

    StagingAppGW[Staging - Application Gateway]
    StagingAKS[Staging - AKS Cluster]
    StagingACR[Staging - Container Registry]

    ProdAppGW[Prod - Application Gateway]
    ProdAKS[Prod - AKS Cluster]
    ProdACR[Prod - Container Registry]

    SharedKV[Azure Key Vault]
    SharedDNS[Azure DNS]
    SharedMonitoring[Log Analytics]

    Internet --> DevAppGW
    Internet --> StagingAppGW
    Internet --> ProdAppGW

    DevAppGW --> DevAKS
    StagingAppGW --> StagingAKS
    ProdAppGW --> ProdAKS

    style DevAppGW fill:#c8e6c9,stroke:#2e7d32
    style DevAKS fill:#c8e6c9,stroke:#2e7d32
    style DevACR fill:#c8e6c9,stroke:#2e7d32
    style StagingAppGW fill:#ffe0b2,stroke:#f57c00
    style StagingAKS fill:#ffe0b2,stroke:#f57c00
    style StagingACR fill:#ffe0b2,stroke:#f57c00
    style ProdAppGW fill:#ffcdd2,stroke:#c62828
    style ProdAKS fill:#ffcdd2,stroke:#c62828
    style ProdACR fill:#ffcdd2,stroke:#c62828
```

## Core Components

### Infrastructure Layer (Terraform-Managed)

#### **Networking**

```mermaid
graph TB
    Internet[Internet]
    AppGW[Application Gateway - WAF v2]

    SystemPool[System Node Pool]
    UserPool[User Node Pool]
    AIPool[AI/ML Node Pool - GPU]

    ACREPE[Container Registry PE]
    KVPE[Key Vault PE]
    StoragePE[Storage Account PE]

    Internet --> AppGW
    AppGW --> SystemPool
    AppGW --> UserPool
    AppGW --> AIPool

    style AppGW fill:#fff3e0,stroke:#e65100
    style SystemPool fill:#e8f5e8,stroke:#1b5e20
    style UserPool fill:#e8f5e8,stroke:#1b5e20
    style AIPool fill:#f8bbd9,stroke:#c2185b
    style ACREPE fill:#e3f2fd,stroke:#0d47a1
    style KVPE fill:#e3f2fd,stroke:#0d47a1
    style StoragePE fill:#e3f2fd,stroke:#0d47a1
```

#### **Compute**
- **AKS Cluster**: Multi-node pool architecture
  - **System Pool**: `Standard_D2s_v3` (2-10 nodes)
  - **User Pool**: `Standard_D2s_v3` (1-10 nodes)  
  - **AI/ML Pool**: `Standard_NC6s_v3` (0-2 nodes, GPU-enabled)

#### **Storage & Data**
- **Azure Container Registry**: Premium tier with private endpoints
- **Azure Key Vault**: Certificate and secret management
- **Storage Accounts**: Terraform state and application data
- **Persistent Volumes**: Azure Disk CSI driver

#### **Security**
- **Azure Active Directory**: Identity and access management
- **Network Security Groups**: Traffic filtering
- **Private Endpoints**: Secure connectivity
- **Application Gateway WAF**: Web application firewall

### Platform Layer (Helm-Managed)

#### **GitOps Platform**

```mermaid
graph TB
    ArgoCDServer[ArgoCD Server - HA]
    AppController[Application Controller]
    RepoServer[Repository Server]
    RedisCache[Redis Cache]
    DexOIDC[Dex - OIDC Integration]

    GitRepo[Git Repository]
    AzureAD[Azure Active Directory]
    K8sAPI[Kubernetes API]

    ArgoCDServer --> AppController
    ArgoCDServer --> RepoServer
    ArgoCDServer --> RedisCache
    ArgoCDServer --> DexOIDC

    RepoServer --> GitRepo
    DexOIDC --> AzureAD
    AppController --> K8sAPI

    style ArgoCDServer fill:#e8f5e8,stroke:#1b5e20
    style AppController fill:#e8f5e8,stroke:#1b5e20
    style RepoServer fill:#e8f5e8,stroke:#1b5e20
    style RedisCache fill:#e8f5e8,stroke:#1b5e20
    style DexOIDC fill:#e8f5e8,stroke:#1b5e20
    style GitRepo fill:#fff3e0,stroke:#e65100
    style AzureAD fill:#e3f2fd,stroke:#0d47a1
    style K8sAPI fill:#f3e5f5,stroke:#4a148c
```

#### **Monitoring Stack**

```mermaid
graph TB
    PrometheusServer[Prometheus Server]
    Alertmanager[Alertmanager]
    NodeExporter[Node Exporter]

    GrafanaServer[Grafana Server]
    Dashboards[Dashboards]
    DataSources[Data Sources]

    Loki[Loki - Log Aggregation]

    NodeExporter --> PrometheusServer
    PrometheusServer --> Alertmanager
    DataSources --> PrometheusServer
    DataSources --> Loki
    GrafanaServer --> Dashboards
    GrafanaServer --> DataSources

    style PrometheusServer fill:#fff3e0,stroke:#e65100
    style Alertmanager fill:#fff3e0,stroke:#e65100
    style NodeExporter fill:#fff3e0,stroke:#e65100
    style GrafanaServer fill:#e8f5e8,stroke:#1b5e20
    style Dashboards fill:#e8f5e8,stroke:#1b5e20
    style DataSources fill:#e8f5e8,stroke:#1b5e20
    style Loki fill:#f3e5f5,stroke:#4a148c
```

#### **AI/ML Platform**

```mermaid
graph TB
    JupyterHubCore[Hub - Multi-user Management]
    JupyterProxy[Proxy - Load Balancing]
    UserPods[User Pods - Jupyter Notebooks]

    MLflowServer[Tracking Server]
    PostgreSQL[PostgreSQL - Metadata]
    MinIO[MinIO - Artifact Storage]

    GPUDriver[Driver Installation]
    DevicePlugin[Device Plugin]
    GPUMonitoring[GPU Monitoring]

    JupyterHubCore --> JupyterProxy
    JupyterProxy --> UserPods
    MLflowServer --> PostgreSQL
    MLflowServer --> MinIO
    UserPods --> MLflowServer

    GPUDriver --> DevicePlugin
    DevicePlugin --> GPUMonitoring
    UserPods -.-> DevicePlugin

    style JupyterHubCore fill:#e8f5e8,stroke:#1b5e20
    style JupyterProxy fill:#e8f5e8,stroke:#1b5e20
    style UserPods fill:#e8f5e8,stroke:#1b5e20
    style MLflowServer fill:#fff3e0,stroke:#e65100
    style PostgreSQL fill:#fff3e0,stroke:#e65100
    style MinIO fill:#fff3e0,stroke:#e65100
    style GPUDriver fill:#f8bbd9,stroke:#c2185b
    style DevicePlugin fill:#f8bbd9,stroke:#c2185b
    style GPUMonitoring fill:#f8bbd9,stroke:#c2185b
```

## Design Principles

### **Infrastructure as Code**
- **Declarative Configuration**: All infrastructure defined in Terraform
- **Version Control**: Infrastructure changes tracked in Git
- **Environment Parity**: Consistent configuration across environments
- **Modular Design**: Reusable Terraform modules

### **GitOps Methodology**
- **Git as Source of Truth**: All configurations stored in Git
- **Automated Deployment**: ArgoCD manages application lifecycle
- **Continuous Reconciliation**: Automatic drift detection and correction
- **Audit Trail**: Complete history of changes

### **Security by Design**
- **Zero Trust Network**: Private endpoints and network segmentation
- **Least Privilege Access**: RBAC and minimal permissions
- **Encryption Everywhere**: Data encrypted at rest and in transit
- **Secret Management**: Azure Key Vault integration

### **Observability First**
- **Comprehensive Monitoring**: Metrics, logs, and traces
- **Proactive Alerting**: Early detection of issues
- **Performance Optimization**: Resource utilization tracking
- **Business Metrics**: Application-specific KPIs

## Data Flow Architecture

### **CI/CD Pipeline Flow**

```mermaid
flowchart LR
    Developer[Developer] --> GitPush[Git Push]
    GitPush --> GitHubActions[GitHub Actions]
    GitHubActions --> Terraform[Terraform Apply]
    Terraform --> AzureResources[Azure Resources]

    GitPush --> GitRepo[Git Repository]
    GitRepo --> ArgoCDSync[ArgoCD Sync]
    ArgoCDSync --> K8sApps[Kubernetes Applications]

    AzureResources -.-> K8sApps
```

### **Application Deployment Flow**

```mermaid
flowchart TD
    GitRepo[Git Repository<br/>App Manifests]
    ArgoCD[ArgoCD<br/>GitOps Controller]
    K8sAPI[Kubernetes API Server]
    AppPods[Application Pods]
    AppGW[Application Gateway<br/>Ingress]
    Users[External Users]

    GitRepo --> ArgoCD
    ArgoCD --> K8sAPI
    K8sAPI --> AppPods
    AppPods --> AppGW
    AppGW --> Users
```

### **Monitoring Data Flow**

```mermaid
flowchart LR
    Apps[Applications]
    LogFiles[Log Files]
    Traces[Traces]

    Prometheus[Prometheus Metrics]
    Loki[Loki Aggregation]
    Jaeger[Jaeger Collection]

    GrafanaDash[Grafana Dashboards]
    GrafanaLogs[Grafana Logs View]
    TracingUI[Distributed Tracing UI]

    Apps --> Prometheus
    Apps --> LogFiles
    Apps --> Traces

    LogFiles --> Loki
    Traces --> Jaeger

    Prometheus --> GrafanaDash
    Loki --> GrafanaLogs
    Jaeger --> TracingUI

    style Apps fill:#e8f5e8,stroke:#1b5e20
    style LogFiles fill:#e8f5e8,stroke:#1b5e20
    style Traces fill:#e8f5e8,stroke:#1b5e20
    style Prometheus fill:#fff3e0,stroke:#e65100
    style Loki fill:#fff3e0,stroke:#e65100
    style Jaeger fill:#fff3e0,stroke:#e65100
    style GrafanaDash fill:#e3f2fd,stroke:#0d47a1
    style GrafanaLogs fill:#e3f2fd,stroke:#0d47a1
    style TracingUI fill:#e3f2fd,stroke:#0d47a1
```

## Network Architecture

### **Traffic Flow**

```mermaid
flowchart TD
    Internet[Internet]
    AppGW[Application Gateway<br/>Public IP]
    LoadBalancer[AKS Internal<br/>Load Balancer]
    AppPods[Application Pods<br/>Private IPs]

    Internet --> AppGW
    AppGW --> LoadBalancer
    LoadBalancer --> AppPods

    style Internet fill:#e1f5fe
    style AppGW fill:#fff3e0
    style LoadBalancer fill:#f3e5f5
    style AppPods fill:#e8f5e8
```

### **Security Zones**
- **DMZ Zone**: Application Gateway subnet
- **Compute Zone**: AKS cluster subnet
- **Data Zone**: Private endpoints subnet
- **Management Zone**: Bastion/jump box (optional)

## Scalability Design

### **Horizontal Scaling**
- **AKS Node Pools**: Auto-scaling based on demand
- **Application Pods**: HPA (Horizontal Pod Autoscaler)
- **Database Connections**: Connection pooling
- **Load Distribution**: Multiple availability zones

### **Vertical Scaling**
- **Resource Limits**: CPU and memory constraints
- **Storage Expansion**: Dynamic volume provisioning
- **Performance Tiers**: Premium storage for critical workloads

## High Availability

### **Infrastructure HA**
- **Multi-Zone Deployment**: Availability zones for resilience
- **Load Balancing**: Traffic distribution across nodes
- **Backup Strategy**: Automated backups for stateful services
- **Disaster Recovery**: Cross-region replication (optional)

### **Application HA**
- **Pod Disruption Budgets**: Maintain minimum replicas
- **Health Checks**: Liveness and readiness probes
- **Circuit Breakers**: Fault tolerance patterns
- **Graceful Shutdown**: Proper termination handling

## Security Architecture

### **Identity and Access**

```mermaid
flowchart TD
    AzureAD[Azure AD<br/>Identity Provider]
    RBAC[RBAC<br/>Role-Based Access Control]
    ServiceAccounts[Service Accounts<br/>Kubernetes]
    PodSecurity[Pod Security Policies]

    AzureAD --> RBAC
    RBAC --> ServiceAccounts
    ServiceAccounts --> PodSecurity

    style AzureAD fill:#e3f2fd
    style RBAC fill:#fff3e0
    style ServiceAccounts fill:#f3e5f5
    style PodSecurity fill:#e8f5e8
```

### **Network Security**

```mermaid
flowchart LR
    Internet[Internet]
    WAF[WAF]
    AppGW[Application Gateway]
    NSG[NSG]
    AKS[AKS]
    NetPol[Network Policies]
    Pods[Pods]

    Internet --> WAF
    WAF --> AppGW
    AppGW --> NSG
    NSG --> AKS
    AKS --> NetPol
    NetPol --> Pods

    style Internet fill:#ffebee
    style WAF fill:#fff3e0
    style AppGW fill:#e8f5e8
    style NSG fill:#e3f2fd
    style AKS fill:#f3e5f5
    style NetPol fill:#fff8e1
    style Pods fill:#e0f2f1
```

### **Data Protection**
- **Encryption at Rest**: Azure Disk Encryption
- **Encryption in Transit**: TLS 1.2+ everywhere
- **Secret Management**: Azure Key Vault CSI driver
- **Certificate Management**: cert-manager with Let's Encrypt

## Performance Considerations

### **Resource Optimization**
- **Right-Sizing**: Appropriate resource requests/limits
- **Caching Strategy**: Redis for session data
- **CDN Integration**: Static content delivery
- **Database Optimization**: Connection pooling and indexing

### **Monitoring and Alerting**
- **SLI/SLO Definition**: Service level objectives
- **Performance Metrics**: Response time, throughput, error rate
- **Capacity Planning**: Resource utilization trends
- **Cost Optimization**: Resource usage analysis

## Technology Stack

### **Infrastructure**
- **Cloud Provider**: Microsoft Azure
- **Container Orchestration**: Azure Kubernetes Service (AKS)
- **Infrastructure as Code**: Terraform
- **CI/CD**: GitHub Actions

### **Platform Services**
- **GitOps**: ArgoCD
- **Monitoring**: Prometheus + Grafana
- **Logging**: Loki
- **Tracing**: Jaeger (optional)
- **Service Mesh**: Istio (optional)

### **AI/ML Stack**
- **Notebooks**: JupyterHub
- **ML Lifecycle**: MLflow
- **GPU Computing**: NVIDIA GPU Operator
- **Model Serving**: Kubeflow (optional)

## Future Considerations

### **Planned Enhancements**
- **Service Mesh**: Istio for advanced traffic management
- **Multi-Cluster**: Federation across regions
- **Advanced AI/ML**: Kubeflow Pipelines integration
- **Compliance**: Additional security frameworks

### **Scalability Roadmap**
- **Global Load Balancing**: Azure Front Door
- **Edge Computing**: Azure IoT Edge integration
- **Hybrid Cloud**: Azure Arc for on-premises
- **Serverless**: Azure Container Instances integration

This architecture provides a solid foundation for modern cloud-native applications while maintaining flexibility for future growth and requirements.
