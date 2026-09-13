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

# Networking and access

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
    error_message = "Be sure to specify at least one CIDR. SSH access should never be open to the entire internet."
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
  description = "DNS label for the public IP. Must be unique within the region and becomes <label>.<region>.cloudapp.azure.com"
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,61}[a-z0-9]$", var.dns_label))
    error_message = "Start with a letter, end with a letter or digit, and use lowercase letters, digits and hyphens only."
  }
}

# Virtual machine

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
}

variable "os_disk_type" {
  description = "Storage account type backing the OS disk."
  type        = string
  default     = "StandardSSD_LRS"
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

# Ubuntu image used by the VM. List available versions with:
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

# Container registry

variable "acr_name" {
  description = "Globally unique name for the container registry. Check availability with: az acr check-name --name <value>"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{5,50}$", var.acr_name))
    error_message = "Use lowercase letters and digits only, between 5 and 50 characters."
  }
}

variable "acr_sku" {
  description = "Azure Container Registry SKU. Basic includes 10 GiB of storage."
  type        = string
  default     = "Basic"
}
