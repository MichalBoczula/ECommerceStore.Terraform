mock_provider "azurerm" {
  mock_resource "azurerm_container_app_environment" {
    override_during = plan
    defaults = {
      id             = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-ecommercestore-dev/providers/Microsoft.App/managedEnvironments/cae-ecommercestore-dev"
      default_domain = "synthetic.francecentral.azurecontainerapps.io"
    }
  }

  mock_resource "azurerm_log_analytics_workspace" {
    override_during = plan
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-ecommercestore-dev/providers/Microsoft.OperationalInsights/workspaces/law-ecommercestore-dev"
    }
  }
}

mock_provider "azapi" {}

variables {
  subscription_id              = "00000000-0000-0000-0000-000000000001"
  sql_admin_password           = "Synthetic-Only-Sql-Password123!"
  mongo_admin_password         = "Synthetic-Only-Mongo-Password123!"
  payments_fulfillment_enabled = true
  app_images = {
    for app, release in jsondecode(file("releases/portfolio.json")).applications :
    app => release.imageReference
    if contains(["bff", "orders", "payments", "products", "users", "web"], app)
  }
}

run "checkout_telemetry_uses_the_dev_workspace" {
  command = plan

  assert {
    condition = (
      azurerm_container_app_environment.store.logs_destination == "azure-monitor" &&
      azurerm_monitor_diagnostic_setting.container_apps.target_resource_id == azurerm_container_app_environment.store.id &&
      azurerm_monitor_diagnostic_setting.container_apps.log_analytics_workspace_id == azurerm_log_analytics_workspace.store.id &&
      azurerm_monitor_diagnostic_setting.container_apps.log_analytics_destination_type == "Dedicated" &&
      toset([for log in azurerm_monitor_diagnostic_setting.container_apps.enabled_log : log.category]) ==
      toset(["ContainerAppConsoleLogs", "ContainerAppSystemLogs"]) &&
      azurerm_application_insights.store.workspace_id == azurerm_log_analytics_workspace.store.id
    )
    error_message = "The DEV workspace must receive Container Apps console and system logs and Application Insights telemetry."
  }

  assert {
    condition = alltrue([
      for name in ["bff", "orders", "payments", "products"] : (
        anytrue([for env in azurerm_container_app.app[name].template[0].container[0].env :
          env.name == "APPLICATIONINSIGHTS_CONNECTION_STRING" && env.secret_name == "application-insights" && env.value == null
        ]) &&
        anytrue([for env in azurerm_container_app.app[name].template[0].container[0].env :
          env.name == "OTEL_SERVICE_NAME" && env.value == "ecommercestore-${name}"
        ])
      )
    ])
    error_message = "Checkout backends must receive the Application Insights secret reference and their own telemetry service name."
  }

  assert {
    condition = alltrue([
      for name in ["users", "web"] : alltrue([
        for env in azurerm_container_app.app[name].template[0].container[0].env :
        !contains(["APPLICATIONINSIGHTS_CONNECTION_STRING", "OTEL_SERVICE_NAME"], env.name)
      ])
    ])
    error_message = "Checkout backend telemetry must be scoped to the checkout services."
  }

  assert {
    condition = (
      anytrue([for env in one(azurerm_container_app_job.payments_fulfillment[0].template[0].container).env :
        env.name == "APPLICATIONINSIGHTS_CONNECTION_STRING" && env.secret_name == "application-insights" && env.value == null
      ]) &&
      anytrue([for env in one(azurerm_container_app_job.payments_fulfillment[0].template[0].container).env :
        env.name == "OTEL_SERVICE_NAME" && env.value == "ecommercestore-payments-fulfillment"
      ])
    )
    error_message = "The fulfillment worker must receive the Application Insights secret reference and its own telemetry service name."
  }
}
