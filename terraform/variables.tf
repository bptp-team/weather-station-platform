variable "subscription_id" {
  description = "Azure subscription ID where the resources will be created."
  type        = string
}

variable "project_name" {
  description = "Short project name used as a prefix for resource names."
  type        = string
  default     = "weather-station"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,20}$", var.project_name))
    error_message = "Use lowercase letters, digits and hyphens only, between 3 and 21 characters."
  }
}

variable "environment" {
  description = "Environment identifier."
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "Accepted values: dev, prod."
  }
}

variable "location" {
  description = "Azure region where the resources will be created."
  type        = string
  default     = "brazilsouth"
}

variable "extra_tags" {
  description = "Additional tags applied to every resource."
  type        = map(string)
  default     = {}
}

# --- Networking and access ---

variable "vnet_address_space" {
  description = "Address space of the virtual network."
  type        = list(string)
  default     = ["10.10.0.0/16"]
}

variable "subnet_address_prefixes" {
  description = "Address prefixes of the subnet hosting the VM."
  type        = list(string)
  default     = ["10.10.1.0/24"]
}

variable "ssh_allowed_cidrs" {
  description = "CIDRs allowed to reach port 22. Use your own IP with a /32 mask."
  type        = list(string)

  validation {
    condition     = length(var.ssh_allowed_cidrs) > 0
    error_message = "Provide at least one CIDR. Leaving SSH open to the internet is not acceptable."
  }
}

variable "http_allowed_cidrs" {
  description = "CIDRs allowed to reach ports 80 and 443."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "mqtt_allowed_cidrs" {
  description = "CIDRs allowed to reach port 1883. Open by default because the ESP32 boards connect from dynamic IPs."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "dns_label" {
  description = "DNS label for the public IP. An empty value generates a label with a random suffix."
  type        = string
  default     = ""
}

# --- Virtual machine ---

variable "vm_size" {
  description = "VM SKU. Standard_B1s includes 750 free hours per month during the first 12 months."
  type        = string
  default     = "Standard_B1s"
}

variable "admin_username" {
  description = "Local administrator user created on the VM."
  type        = string
  default     = "azureuser"
}

variable "ssh_public_key_path" {
  description = "Path to the SSH public key injected into the VM. Must be ssh-rsa with at least 2048 bits, or ssh-ed25519."
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}

variable "os_disk_caching" {
  description = "Caching mode of the OS disk. Accepted values: None, ReadOnly, ReadWrite."
  type        = string
  default     = "ReadWrite"

  validation {
    condition     = contains(["None", "ReadOnly", "ReadWrite"], var.os_disk_caching)
    error_message = "Accepted values: None, ReadOnly, ReadWrite."
  }
}

variable "os_disk_type" {
  description = "Storage account type backing the OS disk."
  type        = string
  default     = "StandardSSD_LRS"

  validation {
    condition = contains(
      ["Standard_LRS", "StandardSSD_LRS", "Premium_LRS", "StandardSSD_ZRS", "Premium_ZRS"],
      var.os_disk_type
    )
    error_message = "Accepted values: Standard_LRS, StandardSSD_LRS, Premium_LRS, StandardSSD_ZRS, Premium_ZRS."
  }
}

variable "os_disk_size_gb" {
  description = "Size of the OS disk in GB. Must be equal to or larger than the size of the source image."
  type        = number
  default     = 30

  validation {
    condition     = var.os_disk_size_gb >= 30
    error_message = "The Ubuntu server image requires at least 30 GB."
  }
}

# Image URNs come from the Azure Marketplace catalog, not from the provider
# documentation. Validate them with:
#   az vm image list --publisher Canonical --offer ubuntu-24_04-lts --all -o table
variable "image_publisher" {
  description = "Publisher of the VM image."
  type        = string
  default     = "Canonical"
}

variable "image_offer" {
  description = "Offer of the VM image."
  type        = string
  default     = "ubuntu-24_04-lts"
}

variable "image_sku" {
  description = "SKU of the VM image."
  type        = string
  default     = "server"
}

variable "image_version" {
  description = "Version of the VM image."
  type        = string
  default     = "latest"
}

# --- Container registry ---

variable "acr_sku" {
  description = "Azure Container Registry SKU. Basic includes 10 GiB of storage."
  type        = string
  default     = "Basic"

  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.acr_sku)
    error_message = "Accepted values: Basic, Standard, Premium."
  }
}
