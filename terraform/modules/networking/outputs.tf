output "vnet_id" {
  description = "ID of the virtual network"
  value       = azurerm_virtual_network.main.id
}

output "vnet_name" {
  description = "Name of the virtual network"
  value       = azurerm_virtual_network.main.name
}

output "aks_subnet_id" {
  description = "ID of the AKS subnet"
  value       = azurerm_subnet.aks.id
}

output "aks_subnet_name" {
  description = "Name of the AKS subnet"
  value       = azurerm_subnet.aks.name
}

output "agc_subnet_id" {
  description = "ID of the Application Gateway for Containers (AGC) subnet"
  value       = azurerm_subnet.agc.id
}

output "agc_subnet_name" {
  description = "Name of the Application Gateway for Containers (AGC) subnet"
  value       = azurerm_subnet.agc.name
}

output "private_endpoints_subnet_id" {
  description = "ID of the private endpoints subnet"
  value       = azurerm_subnet.private_endpoints.id
}

output "private_endpoints_subnet_name" {
  description = "Name of the private endpoints subnet"
  value       = azurerm_subnet.private_endpoints.name
}

output "aks_nsg_id" {
  description = "ID of the AKS network security group"
  value       = azurerm_network_security_group.aks.id
}

output "agc_nsg_id" {
  description = "ID of the Application Gateway for Containers (AGC) network security group"
  value       = azurerm_network_security_group.agc.id
}
