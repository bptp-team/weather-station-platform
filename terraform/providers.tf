provider "azurerm" {
  # Optional per the provider docs: it can also come from ARM_SUBSCRIPTION_ID
  # or from the default subscription selected in the az CLI. Set explicitly
  # so the target subscription is never ambiguous.
  subscription_id = var.subscription_id

  # Since 5.0 the default for resource_provider_registrations is "none".
  # Only the namespaces this module actually needs are registered.
  resource_providers_to_register = [
    "Microsoft.Compute",
    "Microsoft.ContainerRegistry",
    "Microsoft.Network",
  ]

  features {
    # Both default to false since 5.0. They move an invalid location or
    # resource provider name from apply time to plan time.
    # preflight_enabled is left off on purpose: it only covers a subset of
    # resource types and requires live Azure credentials during plan.
    enhanced_validation {
      locations          = true
      resource_providers = true
    }

    virtual_machine {
      delete_os_disk_on_deletion = true
    }
  }
}
