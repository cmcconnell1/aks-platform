# AI/ML Workloads Guide

This guide explains the AI/ML capabilities of the platform, what workloads are deployed, and how to add new GPU-enabled workloads that will be scheduled on the AI node pool.

## Overview

The platform includes a dedicated **AI/ML node pool** with NVIDIA GPU support for running machine learning and data science workloads. This node pool is separate from the system and user node pools to ensure GPU resources are reserved for AI/ML tasks.

## Platform AI/ML Components

### Pre-deployed Workloads

| Component | Description | Namespace | GPU Support |
|-----------|-------------|-----------|-------------|
| **JupyterHub** | Multi-user notebook server for data science | `ai-tools` | Yes |
| **MLflow** | ML lifecycle management (tracking, models, registry) | `ai-tools` | No (tracking server) |
| **NVIDIA GPU Operator** | Manages GPU drivers and device plugins | `gpu-operator` | Required |

### Architecture

```
                    +------------------+
                    |   User Request   |
                    +--------+---------+
                             |
              +--------------+--------------+
              |                             |
    +---------v---------+       +-----------v-----------+
    |    JupyterHub     |       |        MLflow         |
    |   (GPU Notebooks) |       |   (Experiment Track)  |
    +---------+---------+       +-----------+-----------+
              |                             |
              |    +-------------------+    |
              +--->|  AI Node Pool     |<---+
                   |  (GPU-enabled)    |
                   +-------------------+
                           |
                   +-------v-------+
                   | NVIDIA GPU    |
                   | Operator      |
                   +---------------+
```

## AI Node Pool Configuration

### Node Labels

The AI node pool has the following labels that can be used for scheduling:

| Label | Value | Description |
|-------|-------|-------------|
| `node-type` | `ai` | Identifies AI/ML node pool |
| `accelerator` | `nvidia-gpu` | Indicates GPU availability |
| `workload-type` | `ai-ml` | Workload classification |

### Node Taints

The AI node pool has the following taint to prevent non-GPU workloads from being scheduled:

| Taint | Effect | Description |
|-------|--------|-------------|
| `nvidia.com/gpu=true` | `NoSchedule` | Only pods with matching toleration can schedule |

### Checking Node Pool Status

```bash
# List all nodes with labels
kubectl get nodes --show-labels | grep -E "node-type|accelerator"

# Check AI node pool specifically
kubectl get nodes -l node-type=ai

# Describe AI nodes to see GPU resources
kubectl describe nodes -l node-type=ai | grep -A 10 "Allocatable:"

# Check GPU availability
kubectl get nodes -l accelerator=nvidia-gpu -o custom-columns=NAME:.metadata.name,GPU:.status.allocatable.nvidia\\.com/gpu
```

## Scheduling Workloads on GPU Nodes

### Required Pod Configuration

To schedule a pod on the AI node pool, you need **both**:

1. **Toleration** - Allows pod to tolerate the node taint
2. **Node Selector or Affinity** - Targets the AI nodes

### Basic Example

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: gpu-workload
  namespace: ai-tools
spec:
  # Toleration for the GPU taint
  tolerations:
    - key: "nvidia.com/gpu"
      operator: "Equal"
      value: "true"
      effect: "NoSchedule"

  # Node selector to target AI nodes
  nodeSelector:
    node-type: ai

  containers:
    - name: gpu-container
      image: nvidia/cuda:12.0-runtime-ubuntu22.04
      resources:
        limits:
          nvidia.com/gpu: 1  # Request 1 GPU
      command: ["nvidia-smi"]
```

### Deployment Example

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ml-training-job
  namespace: ai-tools
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ml-training
  template:
    metadata:
      labels:
        app: ml-training
    spec:
      tolerations:
        - key: "nvidia.com/gpu"
          operator: "Equal"
          value: "true"
          effect: "NoSchedule"

      nodeSelector:
        node-type: ai
        accelerator: nvidia-gpu

      containers:
        - name: training
          image: pytorch/pytorch:2.0.0-cuda11.7-cudnn8-runtime
          resources:
            limits:
              nvidia.com/gpu: 1
              memory: "16Gi"
              cpu: "4"
            requests:
              memory: "8Gi"
              cpu: "2"
          volumeMounts:
            - name: data
              mountPath: /data

      volumes:
        - name: data
          persistentVolumeClaim:
            claimName: training-data
```

### Node Affinity Example (Advanced)

For more control over scheduling, use node affinity:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: gpu-workload-affinity
spec:
  tolerations:
    - key: "nvidia.com/gpu"
      operator: "Equal"
      value: "true"
      effect: "NoSchedule"

  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
          - matchExpressions:
              - key: node-type
                operator: In
                values:
                  - ai
              - key: accelerator
                operator: In
                values:
                  - nvidia-gpu

  containers:
    - name: gpu-container
      image: nvidia/cuda:12.0-runtime-ubuntu22.04
      resources:
        limits:
          nvidia.com/gpu: 1
```

## JupyterHub GPU Configuration

JupyterHub is pre-configured to spawn GPU-enabled notebook servers:

### Accessing JupyterHub

```bash
# Get the JupyterHub URL
kubectl get httproute -n ai-tools jupyterhub -o jsonpath='{.spec.hostnames[0]}'

# Or access via port-forward
kubectl port-forward -n ai-tools svc/hub 8000:80
```

### User Notebook GPU Access

When users spawn a notebook server in JupyterHub, they can select GPU-enabled profiles:

1. Login to JupyterHub
2. Select a GPU-enabled server profile (if configured)
3. Start the server - it will be scheduled on an AI node
4. Verify GPU access in notebook:

```python
# In Jupyter notebook
import torch
print(f"CUDA available: {torch.cuda.is_available()}")
print(f"GPU count: {torch.cuda.device_count()}")
print(f"GPU name: {torch.cuda.get_device_name(0)}")
```

### Customizing JupyterHub Profiles

To add GPU profiles, update the JupyterHub configuration in `terraform/modules/ai_tools/main.tf`:

```hcl
# Example profile configuration
singleuser = {
  profileList = [
    {
      display_name = "GPU - PyTorch"
      description  = "GPU-enabled notebook with PyTorch"
      kubespawner_override = {
        image = "pytorch/pytorch:2.0.0-cuda11.7-cudnn8-runtime"
        extra_resource_limits = {
          "nvidia.com/gpu" = "1"
        }
        tolerations = [
          {
            key      = "nvidia.com/gpu"
            operator = "Equal"
            value    = "true"
            effect   = "NoSchedule"
          }
        ]
        node_selector = {
          "node-type" = "ai"
        }
      }
    }
  ]
}
```

## MLflow with GPU Training

MLflow tracks experiments but doesn't require GPU itself. Training jobs that log to MLflow need GPU access:

### Training Script Example

```python
import mlflow
import torch

# Set MLflow tracking URI
mlflow.set_tracking_uri("http://mlflow.ai-tools.svc.cluster.local:5000")

# Start experiment
mlflow.set_experiment("gpu-training")

with mlflow.start_run():
    # Log GPU info
    mlflow.log_param("gpu_available", torch.cuda.is_available())
    mlflow.log_param("gpu_name", torch.cuda.get_device_name(0))

    # Your training code here
    model = train_model()

    # Log metrics and model
    mlflow.log_metric("accuracy", accuracy)
    mlflow.pytorch.log_model(model, "model")
```

### MLflow Training Job

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: mlflow-training
  namespace: ai-tools
spec:
  template:
    spec:
      tolerations:
        - key: "nvidia.com/gpu"
          operator: "Equal"
          value: "true"
          effect: "NoSchedule"

      nodeSelector:
        node-type: ai

      containers:
        - name: training
          image: your-registry/ml-training:latest
          env:
            - name: MLFLOW_TRACKING_URI
              value: "http://mlflow:5000"
          resources:
            limits:
              nvidia.com/gpu: 1

      restartPolicy: Never
```

## Adding New AI/ML Workloads

### Step 1: Create Deployment Manifest

Create a Kubernetes manifest with proper GPU configuration:

```yaml
# my-ml-workload.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-ml-workload
  namespace: ai-tools
  labels:
    app: my-ml-workload
    workload-type: ai-ml
spec:
  replicas: 1
  selector:
    matchLabels:
      app: my-ml-workload
  template:
    metadata:
      labels:
        app: my-ml-workload
    spec:
      # REQUIRED: Toleration for GPU nodes
      tolerations:
        - key: "nvidia.com/gpu"
          operator: "Equal"
          value: "true"
          effect: "NoSchedule"

      # REQUIRED: Node selector for AI pool
      nodeSelector:
        node-type: ai

      containers:
        - name: ml-app
          image: your-image:tag
          resources:
            limits:
              nvidia.com/gpu: 1  # Number of GPUs needed
              memory: "16Gi"
            requests:
              memory: "8Gi"
              cpu: "2"
```

### Step 2: Deploy the Workload

```bash
# Apply the manifest
kubectl apply -f my-ml-workload.yaml

# Verify pod is scheduled on AI node
kubectl get pod -n ai-tools -l app=my-ml-workload -o wide

# Check pod is using GPU
kubectl exec -n ai-tools <pod-name> -- nvidia-smi
```

### Step 3: Verify GPU Access

```bash
# Check GPU allocation
kubectl describe pod -n ai-tools <pod-name> | grep -A 5 "Limits:"

# Should show:
#   Limits:
#     nvidia.com/gpu: 1
```

## GPU Resource Management

### Checking GPU Utilization

```bash
# On the node (via debug pod)
kubectl debug node/<ai-node-name> -it --image=nvidia/cuda:12.0-base -- nvidia-smi

# From within a GPU pod
kubectl exec -n ai-tools <pod-name> -- nvidia-smi

# Watch GPU usage
kubectl exec -n ai-tools <pod-name> -- watch -n 1 nvidia-smi
```

### GPU Metrics in Prometheus

The GPU Operator exposes metrics that can be viewed in Grafana:

- `DCGM_FI_DEV_GPU_UTIL` - GPU utilization percentage
- `DCGM_FI_DEV_MEM_USED` - GPU memory used
- `DCGM_FI_DEV_MEM_FREE` - GPU memory free
- `DCGM_FI_DEV_POWER_USAGE` - Power consumption

## Troubleshooting

### Pod Stuck in Pending

```bash
# Check pod events
kubectl describe pod -n ai-tools <pod-name>

# Common issues:
# 1. No available GPU nodes - scale up AI node pool
# 2. Missing toleration - add nvidia.com/gpu toleration
# 3. Wrong node selector - verify node-type=ai exists
```

### GPU Not Detected

```bash
# Check GPU Operator pods
kubectl get pods -n gpu-operator

# Check if GPU is allocatable
kubectl describe node -l node-type=ai | grep nvidia.com/gpu

# Check device plugin logs
kubectl logs -n gpu-operator -l app=nvidia-device-plugin-daemonset
```

### Scale AI Node Pool

```bash
# Scale up AI nodes
az aks nodepool scale \
  --resource-group <rg-name> \
  --cluster-name <cluster-name> \
  --name ai \
  --node-count 2

# Or update via Terraform
# terraform/environments/dev/terraform.tfvars
ai_node_count = 2
```

## Best Practices

### Resource Requests

1. **Always set resource limits** for GPU workloads to prevent resource contention
2. **Request appropriate memory** - GPU workloads often need significant CPU memory too
3. **Use resource quotas** to prevent over-provisioning in shared namespaces

### Workload Isolation

1. **Use separate namespaces** for different teams or projects
2. **Apply NetworkPolicies** to isolate AI workloads if needed
3. **Consider pod priority** for critical training jobs

### Cost Optimization

1. **Scale to zero** when not in use (`min_count = 0` in Terraform)
2. **Use spot instances** for fault-tolerant training jobs
3. **Monitor GPU utilization** and right-size node pool

### Security

1. **Use private container registries** for ML images
2. **Apply pod security policies** for GPU workloads
3. **Secure MLflow tracking server** access

## Related Documentation

- [Architecture Guide](./architecture.md)
- [Environment Configuration](./environment-configuration-guide.md)
- [Troubleshooting Guide](./troubleshooting.md)
- [Cost Monitoring Guide](./cost-monitoring-guide.md)
