mock_provider "azurerm" {}
mock_provider "azapi" {}

variables {
  subscription_id          = "00000000-0000-0000-0000-000000000001"
  sql_admin_password       = "Synthetic-Only-Sql-Password123!"
  mongo_admin_password     = "Synthetic-Only-Mongo-Password123!"
  knowledge_search_enabled = true
  knowledge_runtime_mode   = "azure"
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
    ba            = "docker.io/synthetic/ba@sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
  }
  ba_runtime = {
    foundry_project_endpoint = "https://synthetic.services.ai.azure.com/api/projects/store-dev"
    foundry_agent_version    = "2"
    jira_site_url            = "https://synthetic.atlassian.net"
    jira_email               = "ba@example.test"
    jira_project_key         = "STORE"
    jira_issue_type_id       = "10001"
  }
  ba_api_key        = "synthetic-ba-key-0123456789abcdef"
  ba_mongodb_uri    = "mongodb://example.test/ecommerce_store_ba"
  ba_jira_api_token = "synthetic-jira-token"
}

run "ba_uses_a_pinned_agent_and_runtime_secrets" {
  command = plan

  assert {
    condition = (
      one(azurerm_container_app.app["ba"].identity).type == "SystemAssigned" &&
      one(azurerm_container_app.app["ba"].ingress).target_port == 8080 &&
      toset(keys(output.app_urls)) == toset(["knowledge_api", "ba"])
    )
    error_message = "BA must expose its API in the existing environment with a managed identity."
  }

  assert {
    condition = alltrue([
      for required in [
        { name = "BA_KNOWLEDGE_API_URL", value = "http://ca-ecommercestore-ka-api-dev" },
        { name = "BA_FOUNDRY_AGENT_NAME", value = "ecommerce-business-analyst" },
        { name = "BA_FOUNDRY_AGENT_VERSION", value = "2" },
        ] : anytrue([
          for env in azurerm_container_app.app["ba"].template[0].container[0].env :
          env.name == required.name && env.value == required.value
      ])
    ])
    error_message = "BA must use the selected Foundry version and the environment's Knowledge API."
  }

  assert {
    condition = alltrue([
      for name, secret in {
        BA_API_KEY           = "ba-api-key"
        BA_MONGODB_URI       = "ba-database-uri"
        BA_JIRA_API_TOKEN    = "ba-jira-token"
        BA_KNOWLEDGE_API_KEY = "knowledge-api-key"
        } : anytrue([
          for env in azurerm_container_app.app["ba"].template[0].container[0].env :
          env.name == name && env.secret_name == secret
      ])
    ])
    error_message = "All BA credentials must use Container App secret references."
  }
}
