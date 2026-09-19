variable "subscription_id" {
  description = "Azure subscription ID where the resources will be created."
  type        = string
}

variable "ssh_allowed_cidrs" {
  description = "CIDRs allowed to reach port 22. Use your own IP with a /32 mask."
  type        = list(string)

  validation {
    condition     = length(var.ssh_allowed_cidrs) > 0 && alltrue([for c in var.ssh_allowed_cidrs : can(cidrnetmask(c)) && c != "0.0.0.0/0"])
    error_message = "Specify at least one valid CIDR, such as 203.0.113.10/32. SSH access should never be open to the entire internet."
  }
}

variable "ssh_public_key" {
  description = "Contents of the SSH public key injected into the VM (ssh-ed25519, or ssh-rsa with at least 2048 bits)."
  type        = string
}

variable "dns_label" {
  description = "DNS label for the public IP. Must be unique within the region and becomes <label>.mexicocentral.cloudapp.azure.com"
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,61}[a-z0-9]$", var.dns_label))
    error_message = "Start with a letter, end with a letter or digit, and use lowercase letters, digits and hyphens only."
  }
}

variable "acr_name" {
  description = "Globally unique name for the container registry. Check availability with: az acr check-name --name <value>"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{5,50}$", var.acr_name))
    error_message = "Use lowercase letters and digits only, between 5 and 50 characters."
  }
}
