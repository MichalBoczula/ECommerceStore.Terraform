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
  agent_orchestrator_auth = {
    issuer   = "https://identity.example.test/tenant/v2.0"
    audience = "api://synthetic-orchestrator"
    jwks_url = "https://identity.example.test/tenant/discovery/v2.0/keys"
  }
}

run "deploy_orchestrator_and_mcp" {
  command = plan

  variables {
    app_images = {
      products               = "docker.io/synthetic/products@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
      users                  = "docker.io/synthetic/users@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
      bff                    = "docker.io/synthetic/bff@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
      agent_orchestrator_api = "docker.io/synthetic/ao-api@sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
      agent_orchestrator_web = "docker.io/synthetic/ao-web@sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"
      mcp                    = "docker.io/synthetic/mcp@sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"
    }
  }

  assert {
    condition = (
      toset(keys(output.app_urls)) == toset(keys(var.app_images)) &&
      !one(azurerm_container_app.app["agent_orchestrator_api"].ingress).external_enabled &&
      one(azurerm_container_app.app["agent_orchestrator_web"].ingress).external_enabled &&
      one(azurerm_container_app.app["mcp"].ingress).external_enabled &&
      !one(azurerm_container_app.app["mcp"].ingress).allow_insecure_connections
    )
    error_message = "MCP and Orchestrator Web must be reachable over HTTPS and the Orchestrator API must remain internal."
  }

  assert {
    condition = (
      one(azurerm_container_app.app["agent_orchestrator_api"].template[0].container[0].readiness_probe).path == "/openapi.json" &&
      one(azurerm_container_app.app["mcp"].template[0].container[0].readiness_probe).path == "/health/live" &&
      one(azurerm_container_app.app["agent_orchestrator_web"].template[0].container[0].env).value == "http://ca-ecommercestore-ao-api-dev" &&
      one(azurerm_container_app.app["mcp"].template[0].container[0].env).value == "http://ca-ecommercestore-bff-dev"
    )
    error_message = "Use probes implemented by the published images and same-environment URLs for the internal API and BFF."
  }

  assert {
    condition = (
      output.agent_orchestrator_worker_name == "ca-ecommercestore-ao-worker-dev" &&
      length(azurerm_container_app.agent_orchestrator_worker[0].ingress) == 0 &&
      azurerm_container_app.agent_orchestrator_worker[0].template[0].min_replicas == 1 &&
      azurerm_container_app.agent_orchestrator_worker[0].template[0].container[0].image == var.app_images.agent_orchestrator_api &&
      tolist(azurerm_container_app.agent_orchestrator_worker[0].template[0].container[0].command) == tolist(["python", "-m", "ecommerce_store_agent_orchestrator.worker"]) &&
      one(azurerm_container_app.agent_orchestrator_worker[0].template[0].container[0].env).secret_name == "ao-mongodb-uri" &&
      one(azurerm_container_app.agent_orchestrator_worker[0].secret).value == one(azurerm_container_app.app["agent_orchestrator_api"].secret).value
    )
    error_message = "The independently polling worker must use the API digest and database secret with no ingress."
  }

  assert {
    condition = alltrue([
      for expected in [
        { name = "AO_AUTH_ISSUER", value = var.agent_orchestrator_auth.issuer },
        { name = "AO_AUTH_AUDIENCE", value = var.agent_orchestrator_auth.audience },
        { name = "AO_AUTH_JWKS_URL", value = var.agent_orchestrator_auth.jwks_url },
        ] : anytrue([
          for env in azurerm_container_app.app["agent_orchestrator_api"].template[0].container[0].env :
          env.name == expected.name && env.value == expected.value
      ])
    ])
    error_message = "The API must validate bearer tokens against the configured issuer, audience and JWKS endpoint."
  }
}

run "reject_orchestrator_api_without_auth" {
  command = plan
  variables {
    app_images = {
      agent_orchestrator_api = "docker.io/synthetic/ao-api@sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
    }
    agent_orchestrator_auth = null
  }
  expect_failures = [azurerm_container_app.app]
}

run "configure_worker_authoring" {
  command = plan
  variables {
    app_images = {
      agent_orchestrator_api = "docker.io/synthetic/ao-api@sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
      knowledge_api          = "docker.io/synthetic/knowledge-api@sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"
      ba                     = "docker.io/synthetic/ba@sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"
    }
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
    ba_runtime = {
      foundry_project_endpoint = "https://synthetic.services.ai.azure.com/api/projects/store-dev"
      foundry_agent_version    = "1"
      jira_site_url            = "https://synthetic.atlassian.net"
      jira_email               = "ba@example.test"
      jira_project_key         = "STORE"
      jira_issue_type_id       = "10001"
    }
    ba_api_key                           = "synthetic-ba-key-0123456789abcdef"
    ba_mongodb_uri                       = "mongodb://example.test/ecommerce_store_ba"
    ba_jira_api_token                    = "synthetic-jira-token"
    agent_orchestrator_qa_api_key        = "synthetic-qa-key"
    agent_orchestrator_github_read_token = "synthetic-github-token"
    agent_orchestrator_langsmith_api_key = "synthetic-langsmith-key"
    agent_orchestrator_authoring = {
      qa_api_url      = "https://qa.example.test"
      ba_session_id   = "00000000-0000-4000-8000-000000000001"
      ba_run_id       = "00000000-0000-4000-8000-000000000002"
      draft_sha256    = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
      criterion_index = 2
    }
  }

  assert {
    condition = alltrue([
      for name, secret in {
        AO_BA_API_KEY        = "ba-api-key"
        AO_QA_API_KEY        = "qa-api-key"
        AO_GITHUB_READ_TOKEN = "github-read-token"
        AO_LANGSMITH_API_KEY = "langsmith-api-key"
        } : anytrue([
          for env in azurerm_container_app.agent_orchestrator_worker[0].template[0].container[0].env :
          env.name == name && env.secret_name == secret
      ])
    ]) && toset([for secret in azurerm_container_app.app["agent_orchestrator_api"].secret : secret.name]) == toset(["ao-mongodb-uri"])
    error_message = "Authoring and telemetry credentials must be passed through secret references to the worker alone."
  }

  assert {
    condition = (
      one([
        for env in azurerm_container_app.agent_orchestrator_worker[0].template[0].container[0].env : env.value if env.name == "AO_BA_API_URL"
      ]) == "http://ca-ecommercestore-ba-dev" &&
      one([
        for env in azurerm_container_app.agent_orchestrator_worker[0].template[0].container[0].env : env.value if env.name == "AO_QA_API_URL"
      ]) == "https://qa.example.test" &&
      jsondecode(one([
        for env in azurerm_container_app.agent_orchestrator_worker[0].template[0].container[0].env : env.value if env.name == "AO_SUPPORTED_HANDOFF"
        ])) == {
        baSessionId    = var.agent_orchestrator_authoring.ba_session_id
        baRunId        = var.agent_orchestrator_authoring.ba_run_id
        draftSha256    = var.agent_orchestrator_authoring.draft_sha256
        criterionIndex = var.agent_orchestrator_authoring.criterion_index
      }
    )
    error_message = "The worker must receive both agent URLs and the pinned handoff in the format expected by the published worker."
  }
}

run "reject_orchestrator_web_without_api" {
  command = plan
  variables {
    app_images = {
      agent_orchestrator_web = "docker.io/synthetic/ao-web@sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"
    }
  }
  expect_failures = [azurerm_container_app.app]
}

run "reject_mcp_without_bff" {
  command = plan
  variables {
    app_images = {
      mcp = "docker.io/synthetic/mcp@sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"
    }
  }
  expect_failures = [azurerm_container_app.app]
}

run "reject_authoring_without_ba_and_qa_credentials" {
  command = plan
  variables {
    app_images = {
      agent_orchestrator_api = "docker.io/synthetic/ao-api@sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
    }
    agent_orchestrator_authoring = {
      qa_api_url      = "https://qa.example.test"
      ba_session_id   = "00000000-0000-4000-8000-000000000001"
      ba_run_id       = "00000000-0000-4000-8000-000000000002"
      draft_sha256    = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
      criterion_index = 0
    }
  }
  expect_failures = [azurerm_container_app.agent_orchestrator_worker]
}
