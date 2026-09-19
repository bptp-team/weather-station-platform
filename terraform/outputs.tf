output "resource_group_name" {
  description = "Name of the resource group, used to scope az commands."
  value       = azurerm_resource_group.main.name
}

output "vm_name" {
  description = "Name of the virtual machine."
  value       = azurerm_linux_virtual_machine.main.name
}

output "public_ip_address" {
  description = "Public IP address of the VM."
  value       = azurerm_public_ip.main.ip_address
}

output "public_fqdn" {
  description = "Public DNS name of the VM. Used by the ESP32 firmware and by server_name in edge/nginx.conf."
  value       = azurerm_public_ip.main.fqdn
}

output "acr_name" {
  description = "Name of the container registry, used by az acr login."
  value       = azurerm_container_registry.main.name
}

output "acr_login_server" {
  description = "Registry hostname used in image tags."
  value       = azurerm_container_registry.main.login_server
}
