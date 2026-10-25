locals {
  tags = {
    project     = "ecommercestore"
    environment = "dev"
  }
  app_names = {
    products = "ca-ecommercestore-products-dev"
    bff      = "ca-ecommercestore-bff-dev"
    web      = "ca-ecommercestore-web-dev"
    users    = "ca-ecommercestore-users-dev"
    orders   = "ca-ecommercestore-orders-dev"
    payments = "ca-ecommercestore-payments-dev"
    livedocs = "ca-ecommercestore-livedocs-dev"
  }
  app_urls = {
    for name, app_name in local.app_names :
    name => "https://${app_name}.${azurerm_container_app_environment.store.default_domain}"
  }
}

resource "azurerm_resource_group" "store" {
  name     = "rg-ecommercestore-dev"
  location = var.location
  tags     = local.tags
}

resource "azurerm_container_app_environment" "store" {
  name                  = "cae-ecommercestore-dev"
  resource_group_name   = azurerm_resource_group.store.name
  location              = var.location
  public_network_access = "Enabled"
  tags                  = local.tags

  # No custom VNet and no saved logs. The built-in live log stream still works.
  workload_profile {
    name                  = "Consumption"
    workload_profile_type = "Consumption"
  }
}

resource "azurerm_storage_account" "photos" {
  name                            = var.photo_storage_account_name
  resource_group_name             = azurerm_resource_group.store.name
  location                        = var.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  account_kind                    = "StorageV2"
  access_tier                     = "Hot"
  https_traffic_only_enabled      = true
  min_tls_version                 = "TLS1_2"
  public_network_access           = "Enabled"
  allow_nested_items_to_be_public = true
  tags                            = local.tags
}

resource "azurerm_storage_container" "photos" {
  name                  = "photos"
  storage_account_id    = azurerm_storage_account.photos.id
  container_access_type = "blob"
}
