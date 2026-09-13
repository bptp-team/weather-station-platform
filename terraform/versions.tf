terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.5"
    }
  }

  # State stays local until the Storage Account that will host it exists.
  # The backend block is added once the persistent module is in place.
}
