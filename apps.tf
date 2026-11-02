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
      env = merge(
        {
          ASPNETCORE_ENVIRONMENT                                                        = "Production"
          ASPNETCORE_HTTP_PORTS                                                         = "8080"
          GatewaySettings__BaseUrl                                                      = "http://localhost:8080"
          ReverseProxy__Clusters__products-cluster__Destinations__destination1__Address = local.app_urls.products
          ReverseProxy__Clusters__users-cluster__Destinations__destination1__Address    = local.app_urls.users
        },
        contains(keys(var.app_images), "orders") ? {
          ReverseProxy__Clusters__orders-cluster__Destinations__destination1__Address = local.app_urls.orders
        } : {},
        contains(keys(var.app_images), "payments") ? {
          ReverseProxy__Clusters__payments-cluster__Destinations__destination1__Address = local.app_urls.payments
        } : {},
      )
      secrets    = {}
      secret_env = {}
    }
    web = {
      port       = 80
      live_path  = "/"
      ready_path = "/"
      env        = { BFF_URL = "http://${local.app_names.bff}" }
      secrets    = {}
      secret_env = {}
    }
    users = {
      port       = 8080
      live_path  = "/health/live"
      ready_path = "/health/ready"
      env = {
        ASPNETCORE_ENVIRONMENT               = "Production"
        ASPNETCORE_HTTP_PORTS                = "8080"
        MongoDbSettings__DatabaseName        = "ecommerce-store-users-db"
        MongoDbSettings__InitializeOnStartup = "true"
      }
      secrets = {
        "database-connection" = local.users_connection_string
      }
      secret_env = { MongoDbSettings__ConnectionString = "database-connection" }
    }
    orders = {
      port       = 8080
      live_path  = "/health/live"
      ready_path = "/health/ready"
      env = {
        ASPNETCORE_ENVIRONMENT                    = "Production"
        ASPNETCORE_HTTP_PORTS                     = "8080"
        ASPNETCORE_FORWARDEDHEADERS_ENABLED       = "true"
        MongoDbSettings__DatabaseName             = "ecommerce-store-invoice-db"
        ExternalServices__ProductCatalog__BaseUrl = local.app_urls.products
        InvoiceStorage__ContainerName             = azurerm_storage_container.invoices.name
      }
      secrets = {
        "database-connection"        = local.users_connection_string
        "invoice-storage-connection" = azurerm_storage_account.photos.primary_connection_string
      }
      secret_env = {
        MongoDbSettings__ConnectionString = "database-connection"
        InvoiceStorage__ConnectionString  = "invoice-storage-connection"
      }
    }
    payments = {
      port       = 8080
      live_path  = "/health/live"
      ready_path = "/health/ready"
      env = {
        PAYMENTS_ENVIRONMENT                = "production"
        PAYMENTS_MONGODB_DATABASE_NAME      = "ecommerce-store-payments-db"
        PAYMENTS_ORDERS_API_BASE_URL        = local.app_urls.orders
        PAYMENTS_ORDERS_API_TIMEOUT_SECONDS = "30"
        PAYMENTS_STRIPE_ENABLED             = "false"
      }
      secrets = {
        "database-connection" = local.users_connection_string
      }
      secret_env = { PAYMENTS_MONGODB_CONNECTION_STRING = "database-connection" }
    }
    knowledge_api = {
      port       = 8080
      live_path  = "/health/live"
      ready_path = "/health/ready"
      env = merge({
        KA_CORPUS_PATH     = "/app/data/corpus.json"
        KA_RETRIEVAL_MODE  = var.knowledge_runtime_mode == "demo" ? "local" : "azure"
        KA_GENERATION_MODE = var.knowledge_runtime_mode == "demo" ? "evidence" : "azure"
        }, var.knowledge_runtime_mode == "azure" ? {
        KA_SEARCH_ENDPOINT      = try("https://${azurerm_search_service.knowledge[0].name}.search.windows.net", "")
        KA_SEARCH_INDEX         = var.knowledge_search_index
        KA_OPENAI_ENDPOINT      = var.knowledge_models.endpoint
        KA_EMBEDDING_DEPLOYMENT = var.knowledge_models.embedding_deployment
        KA_EMBEDDING_DIMENSIONS = tostring(var.knowledge_models.embedding_dimensions)
        KA_EMBEDDING_REVISION   = var.knowledge_embedding_revision
        KA_CHAT_DEPLOYMENT      = var.knowledge_models.chat_deployment
      } : {})
      secrets = merge({
        "knowledge-api-key" = var.knowledge_api_key
        }, var.knowledge_runtime_mode == "azure" ? {
        "knowledge-search-key" = try(azurerm_search_service.knowledge[0].query_keys[0].key, null)
        "knowledge-openai-key" = var.knowledge_openai_api_key
      } : {})
      secret_env = merge({
        KA_API_KEY = "knowledge-api-key"
        }, var.knowledge_runtime_mode == "azure" ? {
        KA_SEARCH_KEY = "knowledge-search-key"
        KA_OPENAI_KEY = "knowledge-openai-key"
      } : {})
    }
    knowledge_web = {
      port       = 8080
      live_path  = "/health/live"
      ready_path = "/health/ready"
      env = {
        KNOWLEDGE_API_URL = "http://${local.app_names.knowledge_api}"
      }
      secrets    = { "knowledge-api-key" = var.knowledge_api_key }
      secret_env = { KNOWLEDGE_API_KEY = "knowledge-api-key" }
    }
    pact = {
      port       = 8080
      live_path  = "/health/live"
      ready_path = "/health/ready"
      env = merge({
        ASPNETCORE_ENVIRONMENT = "Production"
        ASPNETCORE_HTTP_PORTS  = "8080"
        Mongo__DatabaseName    = var.pact_mongo_database_name
        Mongo__TimeoutSeconds  = tostring(var.pact_mongo_timeout_seconds)
        }, merge({}, [for publisher, applications in var.pact_publishers : {
          for index, application in sort(tolist(applications)) :
          "RegistryAuth__Publishers__${publisher}__ApplicationIds__${index}" => application
        }]...)
      )
      secrets = merge({ "database-connection" = local.users_connection_string }, {
        for publisher in keys(var.pact_publishers) : "pact-publisher-${publisher}" => lookup(var.pact_publisher_token_sha256, publisher, null)
      })
      secret_env = merge({ Mongo__ConnectionString = "database-connection" }, {
        for publisher in keys(var.pact_publishers) : "RegistryAuth__Publishers__${publisher}__TokenSha256" => "pact-publisher-${publisher}"
      })
    }
    livedocs = {
      port       = 8080
      live_path  = "/health/live"
      ready_path = "/health/ready"
      # CI reads the private Blob archive and builds the static Allure site.
      # The published Nginx image needs no runtime storage credentials or mount.
      env        = {}
      secrets    = {}
      secret_env = {}
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
      username             = var.dockerhub_username
      password_secret_name = "dockerhub-token"
    }
  }

  # Public URLs make each educational app easy to inspect during deployment.
  ingress {
    external_enabled           = each.key == "pact" ? var.pact_ingress_external : true
    allow_insecure_connections = false
    target_port                = local.app_config[each.key].port
    transport                  = "http"
    dynamic "ip_security_restriction" {
      for_each = each.key == "pact" ? { for index, cidr in sort(tolist(var.pact_allowed_ingress_cidrs)) : index => cidr } : {}
      content {
        name             = "pact-ci-${ip_security_restriction.key}"
        action           = "Allow"
        ip_address_range = ip_security_restriction.value
      }
    }
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
      name  = replace(each.key, "_", "-")
      image = each.value
      # Orders renders PDFs; Pact runs bounded comparisons and verification matrices.
      cpu    = contains(["orders", "pact"], each.key) ? 0.5 : 0.25
      memory = contains(["orders", "pact"], each.key) ? "1Gi" : "0.5Gi"

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
      condition = each.key != "pact" || (
        length(var.pact_publishers) > 0 &&
        toset(keys(var.pact_publishers)) == toset(keys(var.pact_publisher_token_sha256))
      )
      error_message = "Pact requires explicit scoped publishers and exactly one distinct token hash for each publisher."
    }
    precondition {
      condition     = each.key != "pact" || can(regex("^docker\\.io/[a-z0-9._-]+/[a-z0-9._-]+@sha256:[a-f0-9]{64}$", each.value))
      error_message = "Deploy Pact using the tested Docker Hub image's immutable docker.io/namespace/repository@sha256 digest."
    }
    precondition {
      condition = each.key != "knowledge_api" || (
        var.knowledge_api_key != null && (
          var.knowledge_runtime_mode == "demo" || (
            var.knowledge_search_enabled &&
            startswith(var.knowledge_models.endpoint, "https://") &&
            length(var.knowledge_models.chat_deployment) > 0 &&
            length(var.knowledge_models.embedding_deployment) > 0 &&
            var.knowledge_openai_api_key != null
          )
        )
      )
      error_message = "Knowledge API requires a shared API key. Azure mode also requires Free Search and complete existing model/key settings."
    }
    precondition {
      condition     = each.key != "knowledge_web" || (contains(keys(var.app_images), "knowledge_api") && var.knowledge_api_key != null)
      error_message = "Knowledge Web requires the knowledge_api image and shared server-side API key."
    }
    precondition {
      condition     = each.key != "bff" || contains(keys(var.app_images), "products")
      error_message = "Keep the products image when adding BFF."
    }
    precondition {
      condition     = each.key != "web" || contains(keys(var.app_images), "bff")
      error_message = "Keep the BFF image when adding Web."
    }
    precondition {
      condition     = each.key != "orders" || contains(keys(var.app_images), "products")
      error_message = "Keep the products image when adding Orders; checkout needs ProductsCatalog."
    }
    precondition {
      condition     = each.key != "payments" || contains(keys(var.app_images), "orders")
      error_message = "Keep the orders image when adding Payments; payment creation needs the Orders API."
    }
  }
}
