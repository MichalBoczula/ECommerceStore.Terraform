locals {
  payments_data_env = {
    PAYMENTS_ENVIRONMENT                = "production"
    PAYMENTS_MONGODB_DATABASE_NAME      = "ecommerce-store-payments-db"
    PAYMENTS_ORDERS_API_BASE_URL        = local.app_urls.orders
    PAYMENTS_ORDERS_API_TIMEOUT_SECONDS = "30"
  }

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
      env = merge(local.payments_data_env, {
        PAYMENTS_STRIPE_ENABLED = tostring(var.payments_stripe_enabled)
        }, var.payments_stripe_enabled ? {
        PAYMENTS_STRIPE_SUCCESS_URL = "${local.app_urls.web}/orders?checkout=success"
        PAYMENTS_STRIPE_CANCEL_URL  = "${local.app_urls.web}/orders?checkout=cancel"
        } : {}, var.payments_stripe_enabled && var.payments_stripe_checkout_vat_enabled ? {
        PAYMENTS_STRIPE_CHECKOUT_VAT_ENABLED = "true"
      } : {})
      secrets = merge({
        "database-connection" = local.users_connection_string
        }, var.payments_stripe_secret_key != null ? {
        "stripe-api-key" = var.payments_stripe_secret_key
        } : {}, var.payments_stripe_webhook_secret != null ? {
        "stripe-webhook-secret" = var.payments_stripe_webhook_secret
      } : {})
      secret_env = merge({
        PAYMENTS_MONGODB_CONNECTION_STRING = "database-connection"
        }, var.payments_stripe_enabled ? {
        PAYMENTS_STRIPE_SECRET_KEY = "stripe-api-key"
        } : {}, var.payments_stripe_webhook_secret != null ? {
        PAYMENTS_STRIPE_WEBHOOK_SECRET = "stripe-webhook-secret"
      } : {})
    }
    knowledge_api = {
      port       = 8080
      live_path  = "/health/live"
      ready_path = "/health/ready"
      env = merge({
        KA_CORPUS_PATH     = "/app/data/corpus.json"
        KA_RETRIEVAL_MODE  = var.knowledge_runtime_mode == "demo" ? "local" : "azure"
        KA_GENERATION_MODE = var.knowledge_runtime_mode == "demo" ? "evidence" : (local.knowledge_foundry_enabled ? "foundry" : "azure")
        }, var.knowledge_runtime_mode == "azure" ? {
        KA_SEARCH_ENDPOINT      = try("https://${azurerm_search_service.knowledge[0].name}.search.windows.net", "")
        KA_SEARCH_INDEX         = var.knowledge_search_index
        KA_OPENAI_ENDPOINT      = var.knowledge_models.endpoint
        KA_EMBEDDING_DEPLOYMENT = var.knowledge_models.embedding_deployment
        KA_EMBEDDING_DIMENSIONS = tostring(var.knowledge_models.embedding_dimensions)
        KA_EMBEDDING_REVISION   = var.knowledge_embedding_revision
        KA_CHAT_DEPLOYMENT      = var.knowledge_models.chat_deployment
        } : {}, local.knowledge_foundry_enabled ? {
        KA_FOUNDRY_PROJECT_ENDPOINT = var.knowledge_foundry_agent.project_endpoint
        KA_FOUNDRY_AGENT_NAME       = var.knowledge_foundry_agent.agent_name
        KA_MAX_OUTPUT_TOKENS        = tostring(var.knowledge_foundry_agent.max_output_tokens)
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
    ba = {
      port       = 8080
      live_path  = "/health/live"
      ready_path = "/health/ready"
      env        = local.ba_env
      secrets = {
        "ba-api-key"        = var.ba_api_key
        "ba-database-uri"   = var.ba_mongodb_uri
        "ba-jira-token"     = var.ba_jira_api_token
        "knowledge-api-key" = var.knowledge_api_key
      }
      secret_env = {
        BA_API_KEY           = "ba-api-key"
        BA_MONGODB_URI       = "ba-database-uri"
        BA_JIRA_API_TOKEN    = "ba-jira-token"
        BA_KNOWLEDGE_API_KEY = "knowledge-api-key"
      }
    }
    qa = {
      port       = 8080
      live_path  = "/health/live"
      ready_path = "/health/ready"
      env = {
        QA_BA_API_URL       = "http://${local.app_names.ba}"
        QA_MONGODB_DATABASE = "ecommerce_store_qa"
      }
      secrets = {
        "qa-api-key"          = var.qa_api_key
        "qa-mongodb-uri"      = var.qa_mongodb_uri != null ? var.qa_mongodb_uri : local.users_connection_string
        "ba-api-key"          = var.ba_api_key
        "qa-e2e-github-token" = var.qa_e2e_github_token
      }
      secret_env = {
        QA_API_KEY          = "qa-api-key"
        QA_MONGODB_URI      = "qa-mongodb-uri"
        QA_BA_API_KEY       = "ba-api-key"
        QA_E2E_GITHUB_TOKEN = "qa-e2e-github-token"
      }
    }
    agent_orchestrator_api = {
      port       = 8080
      live_path  = "/openapi.json"
      ready_path = "/openapi.json"
      env        = local.agent_orchestrator_api_env
      secrets    = { "ao-mongodb-uri" = local.agent_orchestrator_mongodb_uri }
      secret_env = { AO_MONGODB_URI = "ao-mongodb-uri" }
    }
    agent_orchestrator_web = {
      port       = 8080
      live_path  = "/health/live"
      ready_path = "/health/ready"
      env        = merge({ AO_API_URL = "http://${local.app_names.agent_orchestrator_api}" }, local.agent_orchestrator_web_entra_env)
      secrets    = {}
      secret_env = {}
    }
    mcp = {
      port       = 8080
      live_path  = "/health/live"
      ready_path = "/health/live"
      env        = merge({ ECOMMERCE_BFF_BASE_URL = "http://${local.app_names.bff}" }, local.mcp_checkout_auth_env)
      secrets    = var.mcp_checkout_auth == null ? {} : { "mcp-checkout-identity-key" = var.mcp_checkout_identity_key }
      secret_env = var.mcp_checkout_auth == null ? {} : { ECOMMERCE_CHECKOUT_AUTH__IDENTITY_KEY = "mcp-checkout-identity-key" }
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
    pact_web = {
      port       = 8080
      live_path  = "/health/live"
      ready_path = "/health/ready"
      # Server-side Nginx origin, using ACA app-name discovery like the other Web apps.
      env        = { PACT_API_URL = "http://${local.app_names.pact}" }
      secrets    = {}
      secret_env = {}
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

  dynamic "identity" {
    for_each = each.key == "ba" || (each.key == "knowledge_api" && var.knowledge_foundry_agent != null) ? [1] : []
    content {
      type = "SystemAssigned"
    }
  }

  dynamic "secret" {
    for_each = merge(
      local.app_config[each.key].secrets,
      contains(local.checkout_telemetry_apps, each.key) ? {
        (local.application_insights_secret_name) = azurerm_application_insights.store.connection_string
      } : {},
    )
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

  # Orchestrator Web forwards authenticated requests to its internal API.
  ingress {
    external_enabled           = each.key == "pact" ? var.pact_ingress_external : each.key != "agent_orchestrator_api"
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
        for_each = merge(
          local.app_config[each.key].env,
          contains(local.checkout_telemetry_apps, each.key) ? {
            OTEL_SERVICE_NAME = "ecommercestore-${each.key}"
          } : {},
        )
        content {
          name  = env.key
          value = env.value
        }
      }

      dynamic "env" {
        for_each = merge(
          local.app_config[each.key].secret_env,
          contains(local.checkout_telemetry_apps, each.key) ? {
            APPLICATIONINSIGHTS_CONNECTION_STRING = local.application_insights_secret_name
          } : {},
        )
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
      condition = each.key != "ba" || (
        contains(keys(var.app_images), "knowledge_api") && var.knowledge_runtime_mode == "azure" &&
        var.knowledge_api_key != null && var.ba_runtime != null && var.ba_api_key != null &&
        var.ba_mongodb_uri != null && var.ba_jira_api_token != null
      )
      error_message = "BA requires live Knowledge API, Foundry and Jira configuration, MongoDB, and the BA, Knowledge and Jira credentials."
    }
    precondition {
      condition = each.key != "qa" || (
        contains(keys(var.app_images), "ba") && var.ba_api_key != null &&
        var.qa_api_key != null && var.qa_e2e_github_token != null
      )
      error_message = "QA requires the BA deployment and its API key, a QA API key, and the Storefront E2E GitHub token."
    }
    precondition {
      condition     = each.key != "agent_orchestrator_api" || var.agent_orchestrator_auth != null
      error_message = "The Agent Orchestrator API requires an issuer, audience and JWKS endpoint."
    }
    precondition {
      condition     = each.key != "agent_orchestrator_web" || contains(keys(var.app_images), "agent_orchestrator_api")
      error_message = "Keep the Agent Orchestrator API image when adding Agent Orchestrator Web."
    }
    precondition {
      condition     = each.key != "mcp" || contains(keys(var.app_images), "bff")
      error_message = "The storefront MCP server requires the BFF image for its catalog tools."
    }
    precondition {
      condition = each.key != "mcp" || var.mcp_checkout_auth == null || (
        var.mcp_checkout_identity_key != null && var.payments_stripe_enabled && var.payments_fulfillment_enabled
      )
      error_message = "MCP sandbox checkout requires a stable identity key, Stripe sandbox checkout and the Payments fulfillment job."
    }
    precondition {
      condition = each.key != "pact" || (
        length(var.pact_publishers) > 0 &&
        toset(keys(var.pact_publishers)) == toset(keys(var.pact_publisher_token_sha256))
      )
      error_message = "Pact requires explicit scoped publishers and exactly one distinct token hash for each publisher."
    }
    precondition {
      condition     = each.key != "pact_web" || contains(keys(var.app_images), "pact")
      error_message = "Keep the pact API image when adding Pact Web; its anonymous read proxy requires the registry in this environment."
    }
    precondition {
      condition = each.key != "knowledge_api" || (
        var.knowledge_api_key != null && (
          var.knowledge_runtime_mode == "demo" || (
            var.knowledge_search_enabled &&
            can(regex("^https://[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?/openai/v1/?$", var.knowledge_models.endpoint)) &&
            try(length(trimspace(var.knowledge_models.chat_deployment)) > 0, false) &&
            try(length(trimspace(var.knowledge_models.embedding_deployment)) > 0, false) &&
            try(length(trimspace(var.knowledge_openai_api_key)) > 0, false)
          )
        )
      )
      error_message = "Knowledge API requires a shared API key. Azure mode also requires Free Search, an HTTPS /openai/v1 endpoint, chat and embedding deployment names, and a nonblank OpenAI API key."
    }
    precondition {
      condition = each.key != "knowledge_api" || var.knowledge_runtime_mode != "azure" || (
        try(local.release_inventory.applications.knowledge_api.contentMode, "") != "synthetic-demo" ||
        !endswith(each.value, "@${split("@", local.release_inventory.applications.knowledge_api.imageReference)[1]}")
      )
      error_message = "The catalog's synthetic Knowledge API image requires demo mode. Use the indexed refresh image for Azure mode."
    }
    precondition {
      condition     = each.key != "knowledge_web" || (contains(keys(var.app_images), "knowledge_api") && var.knowledge_api_key != null)
      error_message = "Knowledge Web requires the knowledge_api image and shared server-side API key."
    }
    precondition {
      condition     = each.key != "bff" || alltrue([for app in ["products", "users"] : contains(keys(var.app_images), app)])
      error_message = "Keep both products and users images when adding BFF."
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
