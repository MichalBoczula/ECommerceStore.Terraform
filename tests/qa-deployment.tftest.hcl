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
    knowledge_api          = "docker.io/synthetic/knowledge-api@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    ba                     = "docker.io/synthetic/ba@sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
    qa                     = "docker.io/synthetic/qa@sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"
    agent_orchestrator_api = "docker.io/synthetic/ao-api@sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"
  }
  knowledge_search_enabled = true
  knowledge_runtime_mode   = "azure"
  knowledge_api_key        = "synthetic-knowledge-key-0123456789abcdef"
  knowledge_openai_api_key = "synthetic-openai-key"
  knowledge_models = {
    endpoint             = "https://synthetic.openai.azure.com/openai/v1"
    chat_deployment      = "synthetic-chat"
    embedding_deployment = "synthetic-embedding"
    embedding_dimensions = 1536
  }
  ba_runtime = {
    foundry_project_endpoint = "https://synthetic.services.ai.azure.com/api/projects/store-dev"
    foundry_agent_version    = "1"
    jira_site_url            = "https://synthetic.atlassian.net"
    jira_email               = "ba@example.test"
    jira_project_key         = "STORE"
    jira_issue_type_id       = "10001"
  }
  ba_api_key          = "synthetic-ba-key-0123456789abcdef"
  ba_mongodb_uri      = "mongodb://example.test/ecommerce_store_ba"
  ba_jira_api_token   = "synthetic-jira-token"
  qa_api_key          = "synthetic-qa-key"
  qa_e2e_github_token = "synthetic-e2e-publisher"
  agent_orchestrator_auth = {
    issuer   = "https://identity.example.test/tenant/v2.0"
    audience = "api://synthetic-orchestrator"
    jwks_url = "https://identity.example.test/tenant/discovery/v2.0/keys"
  }
  agent_orchestrator_authoring = {
    ba_session_id   = "00000000-0000-4000-8000-000000000001"
    ba_run_id       = "00000000-0000-4000-8000-000000000002"
    draft_sha256    = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    criterion_index = 0
  }
}

run "deploy_qa_and_connect_worker" {
  command = plan

  assert {
    condition = (
      azurerm_container_app.app["qa"].name == "ca-ecommercestore-qa-dev" &&
      contains(keys(output.app_urls), "qa") &&
      one(azurerm_container_app.app["qa"].ingress).external_enabled &&
      !one(azurerm_container_app.app["qa"].ingress).allow_insecure_connections &&
      one(azurerm_container_app.app["qa"].ingress).target_port == 8080 &&
      azurerm_container_app.app["qa"].template[0].min_replicas == 0 &&
      one(azurerm_container_app.app["qa"].template[0].container[0].readiness_probe).path == "/health/ready"
    )
    error_message = "QA must expose its HTTPS origin and use its database readiness probe on the published image port."
  }

  assert {
    condition = alltrue([
      for name, value in {
        QA_BA_API_URL       = "http://ca-ecommercestore-ba-dev"
        QA_MONGODB_DATABASE = "ecommerce_store_qa"
        } : anytrue([
          for env in azurerm_container_app.app["qa"].template[0].container[0].env : env.name == name && env.value == value
      ])
    ])
    error_message = "QA must use the internal BA origin and its own database."
  }

  assert {
    condition = alltrue([
      for name, secret in {
        QA_API_KEY          = "qa-api-key"
        QA_MONGODB_URI      = "qa-mongodb-uri"
        QA_BA_API_KEY       = "ba-api-key"
        QA_E2E_GITHUB_TOKEN = "qa-e2e-github-token"
        } : anytrue([
          for env in azurerm_container_app.app["qa"].template[0].container[0].env : env.name == name && env.secret_name == secret
      ])
      ]) && alltrue([
      for name, value in {
        "qa-api-key"          = var.qa_api_key
        "qa-mongodb-uri"      = local.users_connection_string
        "ba-api-key"          = var.ba_api_key
        "qa-e2e-github-token" = var.qa_e2e_github_token
        } : anytrue([
          for secret in azurerm_container_app.app["qa"].secret : secret.name == name && secret.value == value
      ])
    ])
    error_message = "QA must pass deployment credentials through ACA secret references and default to the shared cluster."
  }

  assert {
    condition = (
      one([
        for env in azurerm_container_app.agent_orchestrator_worker[0].template[0].container[0].env : env.value if env.name == "AO_QA_API_URL"
      ]) == "http://ca-ecommercestore-qa-dev" &&
      one([
        for secret in azurerm_container_app.agent_orchestrator_worker[0].secret : secret.value if secret.name == "qa-api-key"
      ]) == var.qa_api_key
    )
    error_message = "Managed QA authoring must target the internal QA origin and refer to its shared key."
  }
}

run "require_qa_publisher_token" {
  command = plan

  variables {
    qa_e2e_github_token          = null
    agent_orchestrator_authoring = null
  }

  expect_failures = [azurerm_container_app.app]
}
