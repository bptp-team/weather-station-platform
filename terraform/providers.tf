provider "azurerm" {
  subscription_id = var.subscription_id

  resource_providers_to_register = [
    "Microsoft.Compute",
    "Microsoft.ContainerRegistry",
    "Microsoft.Network",
  ]

  features {
    enhanced_validation {
      locations          = true
      resource_providers = true
    }

    virtual_machine {
      delete_os_disk_on_deletion = true
    }
  }
}
