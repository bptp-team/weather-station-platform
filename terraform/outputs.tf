output "resource_group_name" {
  description = "Name of the created resource group."
  value       = azurerm_resource_group.main.name
}

output "vm_name" {
  description = "Name of the virtual machine."
  value       = azurerm_linux_virtual_machine.main.name
}

output "vm_identity_principal_id" {
  description = "Principal ID of the system assigned identity used to pull images."
  value       = azurerm_linux_virtual_machine.main.identity[0].principal_id
}

output "public_ip_address" {
  description = "Public IP address of the VM."
  value       = azurerm_public_ip.main.ip_address
}

output "public_fqdn" {
  description = "Public DNS name of the VM. Used by the ESP32 firmware to reach the broker."
  value       = azurerm_public_ip.main.fqdn
}

output "acr_name" {
  description = "Name of the Azure Container Registry."
  value       = azurerm_container_registry.main.name
}

output "acr_login_server" {
  description = "Registry hostname used in image tags and in the compose file."
  value       = azurerm_container_registry.main.login_server
}
