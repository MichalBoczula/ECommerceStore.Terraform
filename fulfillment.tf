variable "payments_fulfillment_enabled" {
  description = "Run the scheduled Payments fulfillment job in the existing Container Apps environment."
  type        = bool
  default     = false
  nullable    = false
}

resource "azurerm_container_app_job" "payments_fulfillment" {
  count = var.payments_fulfillment_enabled ? 1 : 0

  name                         = "caj-ecommercestore-fulfill-dev"
  location                     = azurerm_resource_group.store.location
  resource_group_name          = azurerm_resource_group.store.name
  container_app_environment_id = azurerm_container_app_environment.store.id
  workload_profile_name        = "Consumption"
  replica_timeout_in_seconds   = 1800
  replica_retry_limit          = 1
  tags                         = local.tags

  schedule_trigger_config {
    cron_expression          = "*/5 * * * *"
    parallelism              = 1
    replica_completion_count = 1
  }

  secret {
    name  = "database-connection"
    value = local.users_connection_string
  }

  dynamic "secret" {
    for_each = var.dockerhub_token == null ? [] : ["dockerhub-token"]
    content {
      name  = secret.value
      value = var.dockerhub_token
    }
  }

  dynamic "registry" {
    for_each = var.dockerhub_token == null ? [] : ["docker.io"]
    content {
      server               = registry.value
      username             = var.dockerhub_username
      password_secret_name = "dockerhub-token"
    }
  }

  template {
    container {
      name    = "payments-fulfillment"
      image   = var.app_images.payments
      cpu     = 0.25
      memory  = "0.5Gi"
      command = ["python", "-m", "ecommerce_store_payments.infrastructure.persistence.mongodb.fulfill_payments"]
      args    = ["--limit", "100"]

      dynamic "env" {
        for_each = local.payments_data_env
        content {
          name  = env.key
          value = env.value
        }
      }

      env {
        name        = "PAYMENTS_MONGODB_CONNECTION_STRING"
        secret_name = "database-connection"
      }
    }
  }

  # Wait for the app deployments, including the Mongo firewall rule they depend on.
  depends_on = [azurerm_container_app.app["payments"], azurerm_container_app.app["orders"]]

  lifecycle {
    precondition {
      condition     = alltrue([for app in ["payments", "orders"] : contains(keys(var.app_images), app)])
      error_message = "Payment fulfillment requires the Payments and Orders images in app_images."
    }
  }
}
