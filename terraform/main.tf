locals {
  name_prefix = "${var.project_name}-${var.environment}"

  # The registry name only accepts alphanumeric characters and must be
  # globally unique, hence the stripped hyphens and the random suffix.
  acr_name = lower(replace("${var.project_name}${var.environment}acr${random_string.suffix.result}", "-", ""))

  dns_label = var.dns_label != "" ? var.dns_label : "${local.name_prefix}-${random_string.suffix.result}"

  tags = merge(
    {
      project     = var.project_name
      environment = var.environment
      managed_by  = "terraform"
    },
    var.extra_tags
  )

  nsg_rules = [
    {
      name         = "allow-ssh"
      priority     = 100
      port         = "22"
      source_cidrs = var.ssh_allowed_cidrs
      description  = "Administrative access, restricted to known addresses."
    },
    {
      name         = "allow-http"
      priority     = 110
      port         = "80"
      source_cidrs = var.http_allowed_cidrs
      description  = "Frontend and ACME HTTP-01 challenge."
    },
    {
      name         = "allow-https"
      priority     = 120
      port         = "443"
      source_cidrs = var.http_allowed_cidrs
      description  = "Frontend and backend API over TLS."
    },
    {
      name         = "allow-mqtt"
      priority     = 130
      port         = "1883"
      source_cidrs = var.mqtt_allowed_cidrs
      description  = "MQTT ingestion from the ESP32 boards."
    },
  ]
}

resource "random_string" "suffix" {
  length  = 6
  lower   = true
  upper   = false
  numeric = true
  special = false
}

# --- Resource group ---

resource "azurerm_resource_group" "main" {
  name     = "${local.name_prefix}-rg"
  location = var.location
  tags     = local.tags
}

# --- Container registry ---

resource "azurerm_container_registry" "main" {
  name                = local.acr_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = var.acr_sku

  # No admin user: pushes come from GitHub Actions through OIDC and pulls
  # come from the VM managed identity via the AcrPull role below.
  admin_enabled = false

  # retention_policy_in_days is deliberately absent: the provider docs state
  # it is only supported on the Premium SKU.

  tags = local.tags
}

# --- Networking ---

resource "azurerm_virtual_network" "main" {
  name                = "${local.name_prefix}-vnet"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  address_space       = var.vnet_address_space
  tags                = local.tags
}

resource "azurerm_subnet" "main" {
  name                 = "${local.name_prefix}-subnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = var.subnet_address_prefixes
}

resource "azurerm_network_security_group" "main" {
  name                = "${local.name_prefix}-nsg"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  tags                = local.tags

  dynamic "security_rule" {
    for_each = local.nsg_rules

    content {
      name                       = security_rule.value.name
      description                = security_rule.value.description
      priority                   = security_rule.value.priority
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = security_rule.value.port
      source_address_prefixes    = security_rule.value.source_cidrs
      destination_address_prefix = "*"
    }
  }
}

resource "azurerm_subnet_network_security_group_association" "main" {
  subnet_id                 = azurerm_subnet.main.id
  network_security_group_id = azurerm_network_security_group.main.id
}

resource "azurerm_public_ip" "main" {
  name                = "${local.name_prefix}-pip"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  # The Standard SKU requires Static allocation. The Basic SKU can no longer
  # be used for new resources since 31 March 2025.
  sku               = "Standard"
  allocation_method = "Static"
  domain_name_label = local.dns_label

  tags = local.tags
}

resource "azurerm_network_interface" "main" {
  name                = "${local.name_prefix}-nic"
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

# --- Virtual machine ---

resource "azurerm_linux_virtual_machine" "main" {
  name                  = "${local.name_prefix}-vm"
  resource_group_name   = azurerm_resource_group.main.name
  location              = azurerm_resource_group.main.location
  size                  = var.vm_size
  admin_username        = var.admin_username
  network_interface_ids = [azurerm_network_interface.main.id]
  tags                  = local.tags

  # Defaults to true, stated explicitly so the intent is visible.
  disable_password_authentication = true

  admin_ssh_key {
    username   = var.admin_username
    public_key = file(pathexpand(var.ssh_public_key_path))
  }

  os_disk {
    name                 = "${local.name_prefix}-osdisk"
    caching              = var.os_disk_caching
    storage_account_type = var.os_disk_type
    disk_size_gb         = var.os_disk_size_gb
  }

  source_image_reference {
    publisher = var.image_publisher
    offer     = var.image_offer
    sku       = var.image_sku
    version   = var.image_version
  }

  identity {
    type = "SystemAssigned"
  }
}

# --- Allows the VM to pull images from the registry ---

resource "azurerm_role_assignment" "vm_acr_pull" {
  scope                = azurerm_container_registry.main.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_linux_virtual_machine.main.identity[0].principal_id
  principal_type       = "ServicePrincipal"

  # The identity is created in this same apply, so the directory lookup can
  # fail from replication lag. The provider documents this flag for exactly
  # that case.
  skip_service_principal_aad_check = true
}
