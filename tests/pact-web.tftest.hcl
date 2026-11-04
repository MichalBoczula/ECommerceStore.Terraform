# Plan-only checks: no Azure calls, backend access or image pulls.
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
}

run "pact_web_is_opt_in" {
  command = plan
  assert {
    condition     = length(azurerm_container_app.app) == 0 && length(azurerm_search_service.knowledge) == 0
    error_message = "Default inputs must keep all apps and optional Search disabled without publisher settings."
  }
}

run "pact_web_uses_shared_environment_and_anonymous_local_proxy" {
  command = plan
  variables {
    app_images = {
      pact     = "docker.io/mb0101/ecommerce-store-pact-api@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
      pact_web = "docker.io/mb0101/ecommerce-store-pact-web@sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
    }
    pact_publishers             = { payments-ci = ["payments"] }
    pact_publisher_token_sha256 = { payments-ci = "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc" }
    pact_ingress_external       = false
  }
  assert {
    condition = length(azurerm_container_app.app) == 2 && alltrue([
      for app in azurerm_container_app.app : app.container_app_environment_id == azurerm_container_app_environment.store.id
    ])
    error_message = "API and Web must share the existing ACA environment as two optional app instances."
  }
  assert {
    condition = (
      azurerm_container_app.app["pact_web"].name == "ca-ecommercestore-pact-web-dev" &&
      azurerm_container_app.app["pact_web"].template[0].container[0].name == "pact-web" &&
      azurerm_container_app.app["pact_web"].template[0].container[0].image == var.app_images.pact_web &&
      length(azurerm_container_app.app["pact_web"].name) <= 32
    )
    error_message = "Pact Web must retain its valid stable ACA/container names and exact image digest."
  }
  assert {
    condition = (
      azurerm_container_app.app["pact_web"].ingress[0].external_enabled &&
      !azurerm_container_app.app["pact_web"].ingress[0].allow_insecure_connections &&
      azurerm_container_app.app["pact_web"].ingress[0].target_port == 8080 &&
      !azurerm_container_app.app["pact"].ingress[0].external_enabled
    )
    error_message = "The HTTPS frontend must target Nginx 8080 without forcing the API's ingress to become public."
  }
  assert {
    condition = (
      length(azurerm_container_app.app["pact_web"].template[0].container[0].env) == 1 &&
      alltrue([for env in azurerm_container_app.app["pact_web"].template[0].container[0].env :
        env.name == "PACT_API_URL" && env.value == "http://${azurerm_container_app.app["pact"].name}" && env.secret_name == null
      ]) && length(azurerm_container_app.app["pact_web"].secret) == 0
    )
    error_message = "Web receives only its server-side app-name origin, without a path, publisher token/hash or database credentials."
  }
  assert {
    condition = (
      azurerm_container_app.app["pact_web"].template[0].min_replicas == 0 &&
      azurerm_container_app.app["pact_web"].template[0].max_replicas == 1 &&
      azurerm_container_app.app["pact_web"].template[0].container[0].cpu == 0.25 &&
      azurerm_container_app.app["pact_web"].template[0].container[0].memory == "0.5Gi" &&
      azurerm_container_app.app["pact_web"].workload_profile_name == "Consumption"
    )
    error_message = "The static frontend must retain Consumption scale-to-zero and the existing small Web resource profile."
  }
  assert {
    condition = alltrue([
      for container in azurerm_container_app.app["pact_web"].template[0].container :
      container.startup_probe[0].path == "/health/live" && container.startup_probe[0].port == 8080 &&
      container.liveness_probe[0].path == "/health/live" && container.liveness_probe[0].port == 8080 &&
      container.readiness_probe[0].path == "/health/ready" && container.readiness_probe[0].port == 8080 &&
      container.startup_probe[0].transport == "HTTP" && container.liveness_probe[0].transport == "HTTP" && container.readiness_probe[0].transport == "HTTP"
    ])
    error_message = "All Web probes must use its local Nginx health endpoints on 8080, independently of API/database readiness."
  }
  assert {
    condition     = toset(keys(output.app_urls)) == toset(["pact", "pact_web"])
    error_message = "The existing enabled-app URL output must include Pact Web without a new output contract."
  }
}

run "pact_web_keeps_existing_apps_and_pact_policy" {
  command = plan
  variables {
    app_images = {
      products      = "example.invalid/products:synthetic"
      bff           = "example.invalid/bff:synthetic"
      web           = "example.invalid/web:synthetic"
      users         = "example.invalid/users:synthetic"
      orders        = "example.invalid/orders:synthetic"
      payments      = "example.invalid/payments:synthetic"
      livedocs      = "example.invalid/livedocs:synthetic"
      knowledge_api = "example.invalid/knowledge-api:synthetic"
      knowledge_web = "example.invalid/knowledge-web:synthetic"
      pact          = "docker.io/mb0101/ecommerce-store-pact-api@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
      pact_web      = "docker.io/mb0101/ecommerce-store-pact-web@sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
    }
    knowledge_runtime_mode      = "demo"
    knowledge_api_key           = "synthetic-test-key-0123456789abcdef"
    pact_publishers             = { payments-ci = ["payments"] }
    pact_publisher_token_sha256 = { payments-ci = "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc" }
    pact_allowed_ingress_cidrs  = ["192.0.2.0/24"]
  }
  assert {
    condition = toset(keys(azurerm_container_app.app)) == toset(keys(var.app_images)) && alltrue([
      for name, image in var.app_images : azurerm_container_app.app[name].template[0].container[0].image == image
    ])
    error_message = "Enabling Pact Web must retain every selected store/Knowledge/API image in the shared app resource."
  }
  assert {
    condition = (
      azurerm_container_app.app["web"].ingress[0].target_port == 80 &&
      anytrue([for env in azurerm_container_app.app["web"].template[0].container[0].env : env.name == "BFF_URL" && env.value == "http://ca-ecommercestore-bff-dev"]) &&
      anytrue([for env in azurerm_container_app.app["knowledge_web"].template[0].container[0].env : env.name == "KNOWLEDGE_API_URL" && env.value == "http://ca-ecommercestore-ka-api-dev"])
    )
    error_message = "Existing Web/Knowledge proxy configuration and ports must remain unchanged."
  }
  assert {
    condition = (
      azurerm_container_app.app["pact"].ingress[0].external_enabled &&
      length(azurerm_container_app.app["pact"].ingress[0].ip_security_restriction) == 1 &&
      alltrue([for rule in azurerm_container_app.app["pact"].ingress[0].ip_security_restriction : rule.ip_address_range == "192.0.2.0/24"]) &&
      length(azurerm_container_app.app["pact_web"].ingress[0].ip_security_restriction) == 0 &&
      length(azurerm_container_app.app["pact"].secret) == 2 && length(azurerm_container_app.app["pact_web"].secret) == 0 &&
      azurerm_container_app.app["pact"].template[0].container[0].cpu == 0.5 &&
      azurerm_container_app.app["pact"].template[0].container[0].memory == "1Gi"
    )
    error_message = "API ingress restrictions, publisher/database secrets and its comparison resource profile must stay API-owned."
  }
  assert {
    condition = length(azurerm_search_service.knowledge) == 0 && alltrue([
      for app in azurerm_container_app.app : app.template[0].min_replicas == 0 && app.template[0].max_replicas == 1
    ])
    error_message = "Adding a dashboard must not enable Search or change the selected apps' scale-to-zero policy."
  }
}

run "pact_web_registry_pull_credentials_are_separate" {
  command = plan
  variables {
    app_images = {
      pact     = "docker.io/mb0101/ecommerce-store-pact-api@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
      pact_web = "docker.io/mb0101/ecommerce-store-pact-web@sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
    }
    pact_publishers             = { payments-ci = ["payments"] }
    pact_publisher_token_sha256 = { payments-ci = "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc" }
    dockerhub_token             = "synthetic-read-only-pull-token"
  }
  assert {
    condition = (
      toset([for secret in azurerm_container_app.app["pact_web"].secret : secret.name]) == toset(["dockerhub-token"]) &&
      length(azurerm_container_app.app["pact_web"].registry) == 1 &&
      alltrue([for registry in azurerm_container_app.app["pact_web"].registry : registry.password_secret_name == "dockerhub-token"]) &&
      length(azurerm_container_app.app["pact_web"].template[0].container[0].env) == 1
    )
    error_message = "An optional image-pull secret may configure the ACA registry but must never enter the Web process environment."
  }
}

run "pact_web_requires_the_pact_api" {
  command = plan
  variables {
    app_images = { pact_web = "docker.io/mb0101/ecommerce-store-pact-web@sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb" }
  }
  expect_failures = [azurerm_container_app.app]
}

run "pact_web_rejects_mutable_image_tags" {
  command = plan
  variables {
    app_images = {
      pact     = "docker.io/mb0101/ecommerce-store-pact-api@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
      pact_web = "docker.io/mb0101/ecommerce-store-pact-web:latest"
    }
    pact_publishers             = { payments-ci = ["payments"] }
    pact_publisher_token_sha256 = { payments-ci = "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc" }
  }
  expect_failures = [azurerm_container_app.app]
}

run "pact_web_rejects_an_incomplete_digest" {
  command = plan
  variables {
    app_images = {
      pact     = "docker.io/mb0101/ecommerce-store-pact-api@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
      pact_web = "docker.io/mb0101/ecommerce-store-pact-web@sha256:1234"
    }
    pact_publishers             = { payments-ci = ["payments"] }
    pact_publisher_token_sha256 = { payments-ci = "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc" }
  }
  expect_failures = [azurerm_container_app.app]
}

run "app_keys_remain_explicit" {
  command = plan
  variables {
    app_images = { pact_frontend = "docker.io/mb0101/ecommerce-store-pact-web:synthetic" }
  }
  expect_failures = [var.app_images]
}
