# These plans use schema-compatible mocks and never connect to Azure or the backend.
mock_provider "azurerm" {}
mock_provider "azapi" {}

variables {
  subscription_id      = "00000000-0000-0000-0000-000000000001"
  sql_admin_password   = "Synthetic-Only-Sql-Password123!"
  mongo_admin_password = "Synthetic-Only-Mongo-Password123!"
}

run "knowledge_disabled_by_default" {
  command = plan

  assert {
    condition     = length(azurerm_search_service.knowledge) == 0 && length(azurerm_container_app.app) == 0
    error_message = "Default inputs must not provision Search or any optional application."
  }

  assert {
    condition     = output.knowledge_search_endpoint == null
    error_message = "Disabled Search must not expose an endpoint."
  }
}

run "knowledge_hosts_use_valid_names" {
  command = plan

  variables {
    knowledge_search_enabled = true
    knowledge_models = {
      endpoint             = "https://synthetic.openai.azure.com/openai/v1/"
      chat_deployment      = "synthetic-chat"
      embedding_deployment = "synthetic-embedding"
      embedding_dimensions = 1536
    }
    knowledge_openai_api_key = "synthetic-test-key"
    knowledge_api_key        = "synthetic-test-key-0123456789abcdef"
    app_images = {
      knowledge_api = "example.invalid/knowledge-api@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
      knowledge_web = "example.invalid/knowledge-web@sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
    }
  }

  assert {
    condition = length(azurerm_container_app.app) == 2 && alltrue([
      for app in azurerm_container_app.app :
      length(app.name) >= 2 && length(app.name) <= 32 &&
      can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", app.name)) && !strcontains(app.name, "--")
    ])
    error_message = "Both Knowledge Container App names must meet Azure's 32-character naming rules."
  }

  assert {
    condition = alltrue(flatten([
      for app in azurerm_container_app.app : [
        for container in app.template[0].container :
        length(container.name) <= 46 && can(regex("^[a-z][a-z0-9.-]*[a-z0-9]$", container.name))
      ]
    ]))
    error_message = "Container names must satisfy the pinned provider's naming rules; underscores are invalid."
  }

  assert {
    condition = anytrue([
      for env in azurerm_container_app.app["knowledge_web"].template[0].container[0].env :
      env.name == "KNOWLEDGE_API_URL" && env.value == "http://${azurerm_container_app.app["knowledge_api"].name}"
    ])
    error_message = "The Web proxy must address the actual API app name."
  }

  assert {
    condition = alltrue([
      for expected in [
        { name = "KA_RETRIEVAL_MODE", value = "azure" },
        { name = "KA_GENERATION_MODE", value = "azure" },
        ] : anytrue([
          for env in azurerm_container_app.app["knowledge_api"].template[0].container[0].env :
          env.name == expected.name && env.value == expected.value
      ])
    ])
    error_message = "The default Azure mode must retain hybrid retrieval and model generation."
  }

  assert {
    condition     = length(azurerm_search_service.knowledge) == 1 && azurerm_search_service.knowledge[0].sku == "free"
    error_message = "Enabling Knowledge must retain the Free Search tier."
  }
}



run "demo_hosts_work_without_search_or_models" {
  command = plan

  variables {
    knowledge_runtime_mode = "demo"
    knowledge_api_key      = "synthetic-test-key-0123456789abcdef"
    app_images = {
      knowledge_api = "example.invalid/knowledge-api@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
      knowledge_web = "example.invalid/knowledge-web@sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
    }
  }

  assert {
    condition     = length(azurerm_container_app.app) == 2 && length(azurerm_search_service.knowledge) == 0
    error_message = "Demo deployment must host both apps without requiring a Search service."
  }

  assert {
    condition = alltrue([
      for expected in [
        { name = "KA_RETRIEVAL_MODE", value = "local" },
        { name = "KA_GENERATION_MODE", value = "evidence" },
        ] : anytrue([
          for env in azurerm_container_app.app["knowledge_api"].template[0].container[0].env :
          env.name == expected.name && env.value == expected.value
      ])
    ])
    error_message = "Demo must use local retrieval and evidence extraction."
  }

  assert {
    condition = toset([
      for secret in azurerm_container_app.app["knowledge_api"].secret : secret.name
    ]) == toset(["knowledge-api-key"])
    error_message = "Demo API must retain proxy authentication without injecting Search or OpenAI keys."
  }

  assert {
    condition = !anytrue([
      for env in azurerm_container_app.app["knowledge_api"].template[0].container[0].env :
      contains(["KA_SEARCH_KEY", "KA_OPENAI_KEY", "KA_OPENAI_ENDPOINT"], env.name)
    ])
    error_message = "Demo must not configure cloud-provider calls."
  }
}
