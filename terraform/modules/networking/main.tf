# Virtual Network
resource "azurerm_virtual_network" "main" {
  name                = "${var.project_name}-${var.environment}-vnet"
  address_space       = var.vnet_address_space
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

# AKS Subnet
resource "azurerm_subnet" "aks" {
  name                 = "${var.project_name}-${var.environment}-aks-subnet"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.aks_subnet_address_prefix]
}

# Application Gateway for Containers (AGC) Subnet
# AGC requires subnet delegation to Microsoft.ServiceNetworking/trafficControllers
resource "azurerm_subnet" "agc" {
  name                 = "${var.project_name}-${var.environment}-agc-subnet"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.agc_subnet_address_prefix]

  delegation {
    name = "agc-delegation"

    service_delegation {
      name = "Microsoft.ServiceNetworking/trafficControllers"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/join/action"
      ]
    }
  }
}

# Private Endpoints Subnet
resource "azurerm_subnet" "private_endpoints" {
  name                 = "${var.project_name}-${var.environment}-pe-subnet"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.private_endpoint_subnet_address_prefix]
}

# Network Security Group for AKS
resource "azurerm_network_security_group" "aks" {
  name                = "${var.project_name}-${var.environment}-aks-nsg"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  # Allow inbound traffic from Application Gateway for Containers (AGC)
  security_rule {
    name                       = "AllowAGC"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["80", "443", "8080", "8443"]
    source_address_prefix      = var.agc_subnet_address_prefix
    destination_address_prefix = var.aks_subnet_address_prefix
  }

  # Allow internal AKS communication
  security_rule {
    name                       = "AllowAKSInternal"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = var.aks_subnet_address_prefix
    destination_address_prefix = var.aks_subnet_address_prefix
  }

  # Allow outbound internet access
  security_rule {
    name                       = "AllowInternetOutbound"
    priority                   = 100
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "Internet"
  }
}

# Associate NSG with AKS subnet
resource "azurerm_subnet_network_security_group_association" "aks" {
  subnet_id                 = azurerm_subnet.aks.id
  network_security_group_id = azurerm_network_security_group.aks.id
}

# Network Security Group for Application Gateway for Containers (AGC)
resource "azurerm_network_security_group" "agc" {
  name                = "${var.project_name}-${var.environment}-agc-nsg"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  # Allow HTTP inbound
  security_rule {
    name                       = "AllowHTTP"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  # Allow HTTPS inbound
  security_rule {
    name                       = "AllowHTTPS"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  # Allow Azure Load Balancer health probes
  security_rule {
    name                       = "AllowAzureLoadBalancer"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "AzureLoadBalancer"
    destination_address_prefix = "*"
  }

  # Allow outbound to AKS cluster
  security_rule {
    name                       = "AllowOutboundToAKS"
    priority                   = 100
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["80", "443", "8080", "8443"]
    source_address_prefix      = "*"
    destination_address_prefix = var.aks_subnet_address_prefix
  }
}

# Associate NSG with AGC subnet
resource "azurerm_subnet_network_security_group_association" "agc" {
  subnet_id                 = azurerm_subnet.agc.id
  network_security_group_id = azurerm_network_security_group.agc.id
}

# Route Table for AKS subnet (if needed for custom routing)
resource "azurerm_route_table" "aks" {
  name                = "${var.project_name}-${var.environment}-aks-rt"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  # Default route to internet (can be customized for hub-spoke topology)
  route {
    name           = "DefaultRoute"
    address_prefix = "0.0.0.0/0"
    next_hop_type  = "Internet"
  }
}

# Associate route table with AKS subnet
resource "azurerm_subnet_route_table_association" "aks" {
  subnet_id      = azurerm_subnet.aks.id
  route_table_id = azurerm_route_table.aks.id
}
