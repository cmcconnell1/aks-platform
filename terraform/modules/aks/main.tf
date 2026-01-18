# AKS Cluster
resource "azurerm_kubernetes_cluster" "main" {
  name                = var.cluster_name
  location            = var.location
  resource_group_name = var.resource_group_name
  dns_prefix          = "${var.project_name}-${var.environment}"
  kubernetes_version  = var.kubernetes_version

  # Private cluster configuration
  private_cluster_enabled         = var.enable_private_cluster
  private_dns_zone_id             = var.enable_private_cluster ? "System" : null
  api_server_authorized_ip_ranges = var.enable_private_cluster ? null : var.authorized_ip_ranges

  # Default node pool
  default_node_pool {
    name                = "system"
    node_count          = var.node_count
    vm_size             = var.node_vm_size
    vnet_subnet_id      = var.vnet_subnet_id
    enable_auto_scaling = true
    min_count           = var.min_node_count
    max_count           = var.max_node_count
    os_disk_size_gb     = var.system_os_disk_size_gb
    os_disk_type        = "Managed"
    type                = "VirtualMachineScaleSets"

    # Note: Default node pool must use Regular priority for system workloads
    # Spot instances are configured in additional node pools only

    # Node labels for system workloads
    node_labels = {
      "node-type" = "system"
    }

    # Taints for system node pool
    node_taints = [
      "CriticalAddonsOnly=true:NoSchedule"
    ]

    upgrade_settings {
      max_surge = var.system_max_surge
    }
  }

  # Identity configuration
  identity {
    type         = "UserAssigned"
    identity_ids = [var.user_assigned_identity_id]
  }

  # Network configuration
  network_profile {
    network_plugin    = "azure"
    network_policy    = "azure"
    dns_service_ip    = var.dns_service_ip
    service_cidr      = var.service_cidr
    load_balancer_sku = "standard"
  }

  # Azure AD integration
  azure_active_directory_role_based_access_control {
    managed                = true
    admin_group_object_ids = []
    azure_rbac_enabled     = true
  }

  # Add-ons
  oms_agent {
    log_analytics_workspace_id = var.log_analytics_workspace_id
  }

  azure_policy_enabled = true

  key_vault_secrets_provider {
    secret_rotation_enabled = true
  }

  # Auto-scaler profile
  auto_scaler_profile {
    balance_similar_node_groups      = var.autoscaler_profile.balance_similar_node_groups
    expander                         = var.autoscaler_profile.expander
    max_graceful_termination_sec     = var.autoscaler_profile.max_graceful_termination_sec
    max_node_provisioning_time       = var.autoscaler_profile.max_node_provisioning_time
    max_unready_nodes                = var.autoscaler_profile.max_unready_nodes
    max_unready_percentage           = var.autoscaler_profile.max_unready_percentage
    new_pod_scale_up_delay           = var.autoscaler_profile.new_pod_scale_up_delay
    scale_down_delay_after_add       = var.autoscaler_profile.scale_down_delay_after_add
    scale_down_delay_after_delete    = var.autoscaler_profile.scale_down_delay_after_delete
    scale_down_delay_after_failure   = var.autoscaler_profile.scale_down_delay_after_failure
    scan_interval                    = var.autoscaler_profile.scan_interval
    scale_down_unneeded              = var.autoscaler_profile.scale_down_unneeded
    scale_down_unready               = var.autoscaler_profile.scale_down_unready
    scale_down_utilization_threshold = var.autoscaler_profile.scale_down_utilization_threshold
  }

  tags = var.tags

  depends_on = [
    azurerm_role_assignment.aks_network_contributor
  ]
}

# User node pool for application workloads
resource "azurerm_kubernetes_cluster_node_pool" "user" {
  name                  = "user"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.main.id
  vm_size               = var.node_vm_size
  node_count            = var.node_count
  vnet_subnet_id        = var.vnet_subnet_id
  enable_auto_scaling   = true
  min_count             = var.min_node_count
  max_count             = var.max_node_count
  os_disk_size_gb       = var.user_os_disk_size_gb
  os_disk_type          = "Managed"

  # Use spot instances if enabled
  priority        = var.enable_spot_instances ? "Spot" : "Regular"
  eviction_policy = var.enable_spot_instances ? "Delete" : null
  spot_max_price  = var.enable_spot_instances ? -1 : null

  node_labels = {
    "node-type" = "user"
  }

  upgrade_settings {
    max_surge = var.user_max_surge
  }

  tags = var.tags
}

# AI/ML node pool with GPU support
resource "azurerm_kubernetes_cluster_node_pool" "ai" {
  count = var.enable_ai_node_pool ? 1 : 0

  name                  = "ai"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.main.id
  vm_size               = var.ai_node_vm_size
  node_count            = var.ai_node_count
  vnet_subnet_id        = var.vnet_subnet_id
  enable_auto_scaling   = true
  min_count             = 0
  max_count             = var.ai_node_count * 2
  os_disk_size_gb       = var.ai_os_disk_size_gb
  os_disk_type          = "Managed"

  node_labels = {
    "node-type"     = "ai"
    "accelerator"   = "nvidia-gpu"
    "workload-type" = "ai-ml"
  }

  node_taints = [
    "nvidia.com/gpu=true:NoSchedule"
  ]

  upgrade_settings {
    max_surge = var.ai_max_surge
  }

  tags = var.tags
}

# Role assignments for AKS managed identity
resource "azurerm_role_assignment" "aks_network_contributor" {
  scope                = var.vnet_subnet_id
  role_definition_name = "Network Contributor"
  principal_id         = var.user_assigned_identity_principal_id
}

resource "azurerm_role_assignment" "aks_acr_pull" {
  scope                = var.container_registry_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_kubernetes_cluster.main.kubelet_identity[0].object_id
}
