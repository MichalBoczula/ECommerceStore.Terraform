locals {
  # Each entry describes the existing application's container contract.
  app_config = {
    products = {
      port       = 8080
      live_path  = "/health/live"
      ready_path = "/health/ready"
      env = {
        ASPNETCORE_ENVIRONMENT    = "Production"
        ASPNETCORE_HTTP_PORTS     = "8080"
        Database__ApplyMigrations = "true"
      }
      secrets = {
        "database-connection" = local.products_connection_string
      }
      secret_env = { ConnectionStrings__ProductCatalogDb = "database-connection" }
    }
    bff = {
      port       = 8080
      live_path  = "/health"
      ready_path = "/health"
      env = {
        ASPNETCORE_ENVIRONMENT                                                        = "Production"
        ASPNETCORE_HTTP_PORTS                                                         = "8080"
        GatewaySettings__BaseUrl                                                      = "http://localhost:8080"
        ReverseProxy__Clusters__products-cluster__Destinations__destination1__Address = local.app_urls.products
        ReverseProxy__Clusters__users-cluster__Destinations__destination1__Address    = local.app_urls.users
      }
      secrets    = {}
      secret_env = {}
    }
    web = {
      port       = 80
      live_path  = "/"
      ready_path = "/"
      env        = {}
      secrets    = {}
      secret_env = {}
    }
    users = {
      port       = 8080
      live_path  = "/health/live"
      ready_path = "/health/ready"
      env = {
        ASPNETCORE_ENVIRONMENT        = "Production"
        ASPNETCORE_HTTP_PORTS         = "8080"
        MongoDbSettings__DatabaseName = "ecommerce-store-users-db"
      }
      secrets = {
        "database-connection" = azurerm_mongo_cluster.users.connection_strings[0].value
      }
      secret_env = { MongoDbSettings__ConnectionString = "database-connection" }
    }
  }
}

resource "azurerm_container_app" "app" {
  for_each = var.app_images

  name                         = local.app_names[each.key]
  resource_group_name          = azurerm_resource_group.store.name
  container_app_environment_id = azurerm_container_app_environment.store.id
  workload_profile_name        = "Consumption"
  revision_mode                = "Single"
  tags                         = local.tags

  dynamic "secret" {
    for_each = local.app_config[each.key].secrets
    content {
      name  = secret.key
      value = secret.value
    }
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
      username             = "mb0101"
      password_secret_name = "dockerhub-token"
    }
  }

  # Public URLs make each educational app easy to inspect during deployment.
  ingress {
    external_enabled           = true
    allow_insecure_connections = false
    target_port                = local.app_config[each.key].port
    transport                  = "http"
    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }

  template {
    min_replicas = 0
    max_replicas = 1

    http_scale_rule {
      name                = "http"
      concurrent_requests = "10"
    }

    container {
      name   = each.key
      image  = each.value
      cpu    = 0.25
      memory = "0.5Gi"

      dynamic "env" {
        for_each = local.app_config[each.key].env
        content {
          name  = env.key
          value = env.value
        }
      }

      dynamic "env" {
        for_each = local.app_config[each.key].secret_env
        content {
          name        = env.key
          secret_name = env.value
        }
      }

      startup_probe {
        transport               = "HTTP"
        port                    = local.app_config[each.key].port
        path                    = local.app_config[each.key].live_path
        interval_seconds        = 5
        timeout                 = 3
        failure_count_threshold = 120
      }
      liveness_probe {
        transport               = "HTTP"
        port                    = local.app_config[each.key].port
        path                    = local.app_config[each.key].live_path
        interval_seconds        = 30
        timeout                 = 3
        failure_count_threshold = 3
      }
      readiness_probe {
        transport               = "HTTP"
        port                    = local.app_config[each.key].port
        path                    = local.app_config[each.key].ready_path
        interval_seconds        = 10
        timeout                 = 5
        failure_count_threshold = 30
      }
    }
  }

  depends_on = [
    azapi_resource.products_database,
    azurerm_mssql_firewall_rule.azure,
    azurerm_mongo_cluster_firewall_rule.azure,
  ]

  lifecycle {
    precondition {
      condition     = each.key != "bff" || contains(keys(var.app_images), "products")
      error_message = "Keep the products image when adding BFF."
    }
    precondition {
      condition     = each.key != "web" || contains(keys(var.app_images), "bff")
      error_message = "Keep the BFF image when adding Web."
    }
  }
}
