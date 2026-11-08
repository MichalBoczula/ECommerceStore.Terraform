mock_provider "azurerm" {
  mock_resource "azurerm_container_app_environment" {
    override_during = plan
    defaults = {
      id             = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-ecommercestore-dev/providers/Microsoft.App/managedEnvironments/cae-ecommercestore-dev"
      default_domain = "synthetic.francecentral.azurecontainerapps.io"
    }
  }
  mock_resource "azurerm_mongo_cluster" {
    override_during = plan
    defaults = {
      id                 = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-ecommercestore-dev/providers/Microsoft.DocumentDB/mongoClusters/synthetic-mongo"
      connection_strings = [{ name = "synthetic", value = "mongodb+srv://synthetic:old-password@synthetic.mongocluster.cosmos.azure.com/?tls=true" }]
    }
  }
}
mock_provider "azapi" {}

variables {
  subscription_id      = "00000000-0000-0000-0000-000000000001"
  sql_admin_password   = "Synthetic-Only-Sql-Password123!"
  mongo_admin_password = "Synthetic-Only-Mongo-Password123!"
  app_images = {
    for app, release in jsondecode(file("releases/portfolio.json")).applications :
    app => release.imageReference if contains(["products", "orders", "payments"], app)
  }
}

run "fulfillment_is_opt_in" {
  command = plan

  assert {
    condition     = length(azurerm_container_app_job.payments_fulfillment) == 0 && output.payments_fulfillment_job_name == null
    error_message = "Existing deployments must keep fulfillment disabled unless explicitly enabled."
  }
}

run "fulfillment_uses_the_payments_release_and_shared_data_settings" {
  command = plan

  variables {
    payments_fulfillment_enabled = true
    # A configured webhook can continue to receive when checkout is paused.
    payments_stripe_webhook_secret = "whsec_synthetic"
    payments_stripe_secret_key     = "sk_test_synthetic"
  }

  assert {
    condition = (
      output.payments_fulfillment_job_name == "caj-ecommercestore-fulfill-dev" &&
      azurerm_container_app_job.payments_fulfillment[0].container_app_environment_id == azurerm_container_app.app["payments"].container_app_environment_id &&
      azurerm_container_app_job.payments_fulfillment[0].resource_group_name == azurerm_container_app.app["payments"].resource_group_name &&
      azurerm_container_app_job.payments_fulfillment[0].workload_profile_name == "Consumption" &&
      azurerm_container_app_job.payments_fulfillment[0].replica_timeout_in_seconds == 1800 &&
      azurerm_container_app_job.payments_fulfillment[0].replica_retry_limit == 1 &&
      azurerm_container_app_job.payments_fulfillment[0].schedule_trigger_config[0].cron_expression == "*/5 * * * *" &&
      azurerm_container_app_job.payments_fulfillment[0].schedule_trigger_config[0].parallelism == 1 &&
      azurerm_container_app_job.payments_fulfillment[0].schedule_trigger_config[0].replica_completion_count == 1
    )
    error_message = "Fulfillment must run one bounded scheduled replica in the existing app environment."
  }

  assert {
    condition = alltrue([
      for container in azurerm_container_app_job.payments_fulfillment[0].template[0].container :
      container.image == var.app_images.payments &&
      container.cpu == 0.25 && container.memory == "0.5Gi" &&
      container.command == tolist(["python", "-m", "ecommerce_store_payments.infrastructure.persistence.mongodb.fulfill_payments"]) &&
      container.args == tolist(["--limit", "100"]) &&
      length(container.startup_probe) == 0 && length(container.readiness_probe) == 0 && length(container.liveness_probe) == 0
    ])
    error_message = "The job must run the bounded one-shot command in the selected Payments image."
  }

  assert {
    condition = (
      tomap({
        for env in one(azurerm_container_app_job.payments_fulfillment[0].template[0].container).env :
        env.name => { value = env.value, secret_name = env.secret_name }
        }) == tomap({
        for env in azurerm_container_app.app["payments"].template[0].container[0].env :
        env.name => { value = env.value, secret_name = env.secret_name }
        if !startswith(env.name, "PAYMENTS_STRIPE_")
      }) &&
      toset([for secret in azurerm_container_app_job.payments_fulfillment[0].secret : secret.name]) == toset(["database-connection"]) &&
      length(azurerm_container_app_job.payments_fulfillment[0].registry) == 0
    )
    error_message = "The job must share Payments' MongoDB and Orders settings without receiving Stripe credentials."
  }
}

run "fulfillment_supports_the_existing_registry_pull_token" {
  command = plan

  variables {
    payments_fulfillment_enabled = true
    dockerhub_token              = "synthetic-dockerhub-pull-token"
  }

  assert {
    condition = (
      toset([for secret in azurerm_container_app_job.payments_fulfillment[0].secret : secret.name]) ==
      toset(["database-connection", "dockerhub-token"]) &&
      one(azurerm_container_app_job.payments_fulfillment[0].registry).server == "docker.io" &&
      one(azurerm_container_app_job.payments_fulfillment[0].registry).username == var.dockerhub_username &&
      one(azurerm_container_app_job.payments_fulfillment[0].registry).password_secret_name == "dockerhub-token"
    )
    error_message = "The optional Docker Hub credential must be scoped to registry pulls."
  }
}

run "fulfillment_requires_the_payments_and_orders_apps" {
  command = plan

  variables {
    app_images                   = {}
    payments_fulfillment_enabled = true
  }

  expect_failures = [azurerm_container_app_job.payments_fulfillment]
}
