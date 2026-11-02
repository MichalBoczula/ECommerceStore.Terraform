mock_provider "azurerm" {
  override_during = plan
  mock_resource "azurerm_mongo_cluster" {
    defaults = {
      connection_strings = [{ name = "synthetic", value = "mongodb+srv://synthetic:old-password@synthetic.mongocluster.cosmos.azure.com/?tls=true" }]
    }
  }
}
mock_provider "azapi" {}

variables {
  subscription_id      = "00000000-0000-0000-0000-000000000001"
  sql_admin_password   = "Synthetic-Only-Sql-Password123!"
  mongo_admin_password = "Synthetic-Only-Mongo-Password123!"
}

run "pact_disabled_by_default" {
  command = plan
  assert {
    condition     = !contains(keys(azurerm_container_app.app), "pact")
    error_message = "Default inputs must not deploy Pact or require publisher credentials."
  }
}

run "pact_reuses_shared_infrastructure_and_scoped_secrets" {
  command = plan
  variables {
    app_images = { pact = "docker.io/mb0101/ecommerce-store-pact-api@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" }
    pact_publishers = {
      payments-ci = ["payments"]
      invoice-ci  = ["invoice"]
    }
    pact_publisher_token_sha256 = {
      payments-ci = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
      invoice-ci  = "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"
    }
    pact_allowed_ingress_cidrs = ["192.0.2.0/24"]
  }
  assert {
    condition     = length(azurerm_container_app.app) == 1 && azurerm_container_app.app["pact"].container_app_environment_id == azurerm_container_app_environment.store.id
    error_message = "Pact must be one optional app in the existing environment."
  }
  assert {
    condition     = azurerm_container_app.app["pact"].name == "ca-ecommercestore-pact-dev" && azurerm_container_app.app["pact"].template[0].min_replicas == 0 && azurerm_container_app.app["pact"].template[0].max_replicas == 1
    error_message = "Pact must use the stable app name and scale from zero to one."
  }
  assert {
    condition = alltrue([
      for expected in [
        { name = "Mongo__DatabaseName", value = "ecommerce-store-pact-db" },
        { name = "Mongo__TimeoutSeconds", value = "3" },
        { name = "RegistryAuth__Publishers__payments-ci__ApplicationIds__0", value = "payments" },
        { name = "RegistryAuth__Publishers__invoice-ci__ApplicationIds__0", value = "invoice" },
        ] : anytrue([
          for env in azurerm_container_app.app["pact"].template[0].container[0].env : env.name == expected.name && env.value == expected.value
      ])
    ])
    error_message = "Pact must use its separate database, bounded timeout and explicit service scopes."
  }
  assert {
    condition = alltrue([
      for expected in [
        { name = "Mongo__ConnectionString", secret = "database-connection" },
        { name = "RegistryAuth__Publishers__payments-ci__TokenSha256", secret = "pact-publisher-payments-ci" },
        { name = "RegistryAuth__Publishers__invoice-ci__TokenSha256", secret = "pact-publisher-invoice-ci" },
        ] : anytrue([
          for env in azurerm_container_app.app["pact"].template[0].container[0].env : env.name == expected.name && env.secret_name == expected.secret && env.value == null
      ])
    ])
    error_message = "Mongo credentials and token hashes must be ACA secret references, not plaintext environment values."
  }
  assert {
    condition     = length(azurerm_container_app.app["pact"].secret) == 3 && length(azurerm_container_app.app["pact"].ingress[0].ip_security_restriction) == 1 && !azurerm_container_app.app["pact"].ingress[0].allow_insecure_connections
    error_message = "Pact must inject only its connection/hash secrets and use HTTPS with its selected ingress restriction."
  }
  assert {
    condition = alltrue([
      for container in azurerm_container_app.app["pact"].template[0].container :
      container.startup_probe[0].path == "/health/live" && container.liveness_probe[0].path == "/health/live" && container.readiness_probe[0].path == "/health/ready" && container.readiness_probe[0].port == 8080
    ])
    error_message = "Probes must separate process liveness/startup from MongoDB readiness."
  }
}

run "pact_requires_publisher_configuration" {
  command = plan
  variables {
    app_images = { pact = "docker.io/mb0101/ecommerce-store-pact-api@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" }
  }
  expect_failures = [azurerm_container_app.app]
}

run "pact_rejects_mutable_image_tag" {
  command = plan
  variables {
    app_images                  = { pact = "docker.io/mb0101/ecommerce-store-pact-api:latest" }
    pact_publishers             = { payments-ci = ["payments"] }
    pact_publisher_token_sha256 = { payments-ci = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb" }
  }
  expect_failures = [azurerm_container_app.app]
}

run "pact_rejects_wildcard_scopes" {
  command = plan
  variables { pact_publishers = { payments-ci = ["*"] } }
  expect_failures = [var.pact_publishers]
}

run "pact_rejects_duplicate_token_hashes" {
  command = plan
  variables {
    pact_publisher_token_sha256 = {
      payments-ci = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
      invoice-ci  = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
    }
  }
  expect_failures = [var.pact_publisher_token_sha256]
}
