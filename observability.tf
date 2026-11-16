locals {
  checkout_telemetry_apps          = toset(["bff", "orders", "payments", "products"])
  application_insights_secret_name = "application-insights"
}

resource "azurerm_log_analytics_workspace" "store" {
  name                = "law-ecommercestore-dev"
  resource_group_name = azurerm_resource_group.store.name
  location            = azurerm_resource_group.store.location
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = local.tags
}

resource "azurerm_application_insights" "store" {
  name                = "appi-ecommercestore-dev"
  resource_group_name = azurerm_resource_group.store.name
  location            = azurerm_resource_group.store.location
  application_type    = "web"
  workspace_id        = azurerm_log_analytics_workspace.store.id
  tags                = local.tags
}

resource "azurerm_monitor_diagnostic_setting" "container_apps" {
  name                           = "container-apps-logs"
  target_resource_id             = azurerm_container_app_environment.store.id
  log_analytics_workspace_id     = azurerm_log_analytics_workspace.store.id
  log_analytics_destination_type = "Dedicated"

  enabled_log {
    category = "ContainerAppConsoleLogs"
  }

  enabled_log {
    category = "ContainerAppSystemLogs"
  }
}
