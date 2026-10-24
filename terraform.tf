terraform {
  required_version = ">= 1.13.1, < 2.0.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "= 5.9.0"
    }
    # AzureRM does not expose the SQL Free offer settings.
    azapi = {
      source  = "Azure/azapi"
      version = "= 2.13.0"
    }
  }

  # Existing storage from the screenshot. This root never creates/deletes it.
  backend "azurerm" {
    storage_account_name = "stecomtfstatemb261011"
    container_name       = "tfstate"
    key                  = "ecommerce-store/simple-dev.terraform.tfstate"
    use_azuread_auth     = true
    use_cli              = true
  }
}

provider "azurerm" {
  subscription_id = var.subscription_id
  use_cli         = true

  resource_provider_registrations = "none"
  resource_providers_to_register = [
    "Microsoft.App",
    "Microsoft.DocumentDB",
    "Microsoft.Network",
    "Microsoft.Sql",
    "Microsoft.Storage",
  ]

  features {}
}

provider "azapi" {
  subscription_id = var.subscription_id
  use_cli         = true
}
