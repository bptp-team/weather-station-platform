terraform {
  required_version = "~> 1.9"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.5"
    }
  }

  # Created once outside Terraform. See "State" in the README.
  backend "azurerm" {
    resource_group_name  = "weather-station-tfstate-rg"
    storage_account_name = "weatherstationtfstate"
    container_name       = "tfstate"
    key                  = "weather-station.tfstate"
    use_azuread_auth     = true
  }
}
