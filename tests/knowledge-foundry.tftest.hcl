mock_provider "azurerm" {}
mock_provider "azapi" {}

variables {
  subscription_id          = "00000000-0000-0000-0000-000000000001"
  sql_admin_password       = "Synthetic-Only-Sql-Password123!"
  mongo_admin_password     = "Synthetic-Only-Mongo-Password123!"
  knowledge_search_enabled = true
  knowledge_api_key        = "synthetic-test-key-0123456789abcdef"
  knowledge_openai_api_key = "synthetic-test-key"
  knowledge_models = {
    endpoint             = "https://synthetic.openai.azure.com/openai/v1"
    chat_deployment      = "synthetic-chat"
    embedding_deployment = "synthetic-embedding"
    embedding_dimensions = 1536
  }
  app_images = {
    knowledge_api = "docker.io/synthetic/knowledge-api@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    knowledge_web = "docker.io/synthetic/knowledge-web@sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
  }
  knowledge_foundry_agent = {
    project_endpoint = "https://synthetic.services.ai.azure.com/api/projects/store-dev"
    agent_name       = "ecommerce-knowledge-assistant"
  }
}

run "stage_api_identity_before_using_foundry" {
  command = plan

  assert {
    condition = (
      one(azurerm_container_app.app["knowledge_api"].identity).type == "SystemAssigned" &&
      length(azurerm_container_app.app["knowledge_web"].identity) == 0
    )
    error_message = "Provision a system-assigned identity only for the Knowledge API."
  }

  assert {
    condition = anytrue([
      for env in azurerm_container_app.app["knowledge_api"].template[0].container[0].env :
      env.name == "KA_GENERATION_MODE" && env.value == "azure"
    ])
    error_message = "Staging the identity must continue to use the existing model generation mode."
  }
}

run "enable_saved_agent_for_generation" {
  command = plan

  variables {
    knowledge_foundry_agent = {
      project_endpoint  = "https://synthetic.services.ai.azure.com/api/projects/store-dev"
      agent_name        = "ecommerce-knowledge-assistant"
      enabled           = true
      max_output_tokens = 4096
    }
  }

  assert {
    condition = alltrue([
      for expected in [
        { name = "KA_GENERATION_MODE", value = "foundry" },
        { name = "KA_RETRIEVAL_MODE", value = "azure" },
        { name = "KA_FOUNDRY_PROJECT_ENDPOINT", value = "https://synthetic.services.ai.azure.com/api/projects/store-dev" },
        { name = "KA_FOUNDRY_AGENT_NAME", value = "ecommerce-knowledge-assistant" },
        { name = "KA_MAX_OUTPUT_TOKENS", value = "4096" },
        ] : anytrue([
          for env in azurerm_container_app.app["knowledge_api"].template[0].container[0].env :
          env.name == expected.name && env.value == expected.value
      ])
    ])
    error_message = "Enable Foundry generation with the configured agent, while retaining Azure retrieval."
  }
}
