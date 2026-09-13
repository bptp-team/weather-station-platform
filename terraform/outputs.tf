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
  description = "Public DNS name of the VM. Use this value in the ESP32 firmware."
  value       = azurerm_public_ip.main.fqdn
}

output "ssh_command" {
  description = "Ready to use command to reach the VM."
  value       = "ssh ${var.admin_username}@${azurerm_public_ip.main.fqdn}"
}

output "acr_name" {
  description = "Name of the Azure Container Registry."
  value       = azurerm_container_registry.main.name
}

output "acr_login_server" {
  description = "Registry hostname used in image tags and in the compose file."
  value       = azurerm_container_registry.main.login_server
}

output "ansible_inventory" {
  description = "Inventory ready for Ansible. Redirect it to ansible/inventory/hosts.yml."

  value = yamlencode({
    weather_station = {
      hosts = {
        (azurerm_linux_virtual_machine.main.name) = {
          ansible_host = azurerm_public_ip.main.ip_address
          ansible_user = var.admin_username
        }
      }
      vars = {
        acr_login_server = azurerm_container_registry.main.login_server
        public_fqdn      = azurerm_public_ip.main.fqdn
      }
    }
  })
}
