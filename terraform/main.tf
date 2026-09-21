locals {
  tags = {
    project    = "weather-station"
    managed_by = "terraform"
  }
}

resource "azurerm_resource_group" "main" {
  name     = "weather-station-rg"
  location = "mexicocentral"
  tags     = local.tags
}

resource "azurerm_container_registry" "main" {
  name                = var.acr_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = "Basic"
  admin_enabled       = false
  tags                = local.tags
}

resource "azurerm_virtual_network" "main" {
  name                = "weather-station-vnet"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  address_space       = ["10.10.0.0/16"]
  tags                = local.tags
}

resource "azurerm_subnet" "main" {
  name                 = "weather-station-subnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.10.1.0/24"]
}

resource "azurerm_network_security_group" "main" {
  name                = "weather-station-nsg"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  tags                = local.tags

  security_rule {
    name                       = "allow-ssh"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefixes    = var.ssh_allowed_cidrs
    destination_address_prefix = "*"
  }

  # 80 also serves the ACME HTTP-01 challenge.
  security_rule {
    name                       = "allow-web"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["80", "443"]
    source_address_prefix      = "Internet"
    destination_address_prefix = "*"
  }

  # The ESP32 boards connect from dynamic addresses.
  security_rule {
    name                       = "allow-mqtt"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "1883"
    source_address_prefix      = "Internet"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "main" {
  subnet_id                 = azurerm_subnet.main.id
  network_security_group_id = azurerm_network_security_group.main.id
}

resource "azurerm_public_ip" "main" {
  name                = "weather-station-pip"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = "Standard"
  allocation_method   = "Static"
  domain_name_label   = var.dns_label
  tags                = local.tags
}

resource "azurerm_network_interface" "main" {
  name                = "weather-station-nic"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  tags                = local.tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.main.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.main.id
  }
}

resource "azurerm_linux_virtual_machine" "main" {
  name                            = "weather-station-vm"
  resource_group_name             = azurerm_resource_group.main.name
  location                        = azurerm_resource_group.main.location
  size                            = "Standard_B2ats_v2"
  admin_username                  = "azureuser"
  network_interface_ids           = [azurerm_network_interface.main.id]
  disable_password_authentication = true
  tags                            = local.tags

  admin_ssh_key {
    username   = "azureuser"
    public_key = var.ssh_public_key
  }

  os_disk {
    name                 = "weather-station-osdisk"
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
    disk_size_gb         = 30
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }

  identity {
    type = "SystemAssigned"
  }

  # The OS disk holds the InfluxDB data, the broker state and the ACME certificate.
  # lifecycle {
  #   prevent_destroy = true
  # }
}

resource "azurerm_role_assignment" "vm_acr_pull" {
  scope                            = azurerm_container_registry.main.id
  role_definition_name             = "AcrPull"
  principal_id                     = azurerm_linux_virtual_machine.main.identity[0].principal_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}

# Deployment identities

# The tenant forbids application registrations, so the pipelines authenticate with
# user-assigned identities, which are subscription resources.
resource "azurerm_user_assigned_identity" "backend_cd" {
  name                = "weather-station-backend-cd"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  tags                = local.tags
}

resource "azurerm_user_assigned_identity" "frontend_cd" {
  name                = "weather-station-frontend-cd"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  tags                = local.tags
}

# The subject must match the repository and the GitHub environment exactly.
resource "azurerm_federated_identity_credential" "backend_cd" {
  name                      = "github-production"
  user_assigned_identity_id = azurerm_user_assigned_identity.backend_cd.id
  audience                  = ["api://AzureADTokenExchange"]
  issuer                    = "https://token.actions.githubusercontent.com"
  subject                   = "repo:${var.github_owner}/weather-station-backend:environment:production"
}

resource "azurerm_federated_identity_credential" "frontend_cd" {
  name                      = "github-production"
  user_assigned_identity_id = azurerm_user_assigned_identity.frontend_cd.id
  audience                  = ["api://AzureADTokenExchange"]
  issuer                    = "https://token.actions.githubusercontent.com"
  subject                   = "repo:${var.github_owner}/weather-station-frontend:environment:production"
}

resource "azurerm_role_assignment" "backend_cd_acr_push" {
  scope                            = azurerm_container_registry.main.id
  role_definition_name             = "AcrPush"
  principal_id                     = azurerm_user_assigned_identity.backend_cd.principal_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}

resource "azurerm_role_assignment" "frontend_cd_acr_push" {
  scope                            = azurerm_container_registry.main.id
  role_definition_name             = "AcrPush"
  principal_id                     = azurerm_user_assigned_identity.frontend_cd.principal_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}

# Virtual Machine Contributor would also allow deleting the VM, and its disk holds
# the InfluxDB data. Run Command alone is enough to deploy.
resource "azurerm_role_definition" "deployer" {
  name        = "Weather Station Deployer"
  scope       = azurerm_linux_virtual_machine.main.id
  description = "Runs deployment commands on the weather station VM."

  permissions {
    actions = [
      "Microsoft.Compute/virtualMachines/read",
      "Microsoft.Compute/virtualMachines/runCommand/action",
    ]
  }

  assignable_scopes = [azurerm_linux_virtual_machine.main.id]
}

resource "azurerm_role_assignment" "backend_cd_deployer" {
  scope                            = azurerm_linux_virtual_machine.main.id
  role_definition_id               = azurerm_role_definition.deployer.role_definition_resource_id
  principal_id                     = azurerm_user_assigned_identity.backend_cd.principal_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}

resource "azurerm_role_assignment" "frontend_cd_deployer" {
  scope                            = azurerm_linux_virtual_machine.main.id
  role_definition_id               = azurerm_role_definition.deployer.role_definition_resource_id
  principal_id                     = azurerm_user_assigned_identity.frontend_cd.principal_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}
