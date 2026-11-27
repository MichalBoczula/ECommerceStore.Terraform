variable "agent_orchestrator_auth" {
  description = "Issuer, audience and JWKS endpoint expected by the Agent Orchestrator API."
  type = object({
    issuer   = string
    audience = string
    jwks_url = string
  })
  default = null

  validation {
    condition = var.agent_orchestrator_auth == null ? true : (
      can(regex("^https://[A-Za-z0-9][A-Za-z0-9.:/-]*$", var.agent_orchestrator_auth.issuer)) &&
      try(length(trimspace(var.agent_orchestrator_auth.audience)) > 0, false) &&
      can(regex("^https://[A-Za-z0-9][A-Za-z0-9.:/_-]*$", var.agent_orchestrator_auth.jwks_url))
    )
    error_message = "Supply the exact token audience and HTTPS issuer and JWKS URLs for the Agent Orchestrator API."
  }
}

variable "agent_orchestrator_mongodb_uri" {
  description = "Optional MongoDB URI for the Agent Orchestrator API and worker. Defaults to the existing DEV DocumentDB cluster."
  type        = string
  sensitive   = true
  default     = null

  validation {
    condition     = var.agent_orchestrator_mongodb_uri == null ? true : can(regex("^mongodb(\\+srv)?://[^[:space:]]+$", var.agent_orchestrator_mongodb_uri))
    error_message = "Supply a MongoDB connection URI for the Agent Orchestrator."
  }
}

variable "agent_orchestrator_authoring" {
  description = "Optional published BA catalog handoff pinned by the worker. Set qa_api_url when using an external QA API."
  type = object({
    qa_api_url      = optional(string)
    ba_session_id   = string
    ba_run_id       = string
    draft_sha256    = string
    criterion_index = number
  })
  default = null

  validation {
    condition = var.agent_orchestrator_authoring == null ? true : (
      (var.agent_orchestrator_authoring.qa_api_url == null || can(regex("^https://[A-Za-z0-9][A-Za-z0-9.-]*(:[0-9]+)?/?$", var.agent_orchestrator_authoring.qa_api_url))) &&
      alltrue([for id in [var.agent_orchestrator_authoring.ba_session_id, var.agent_orchestrator_authoring.ba_run_id] : can(regex("^[0-9A-Fa-f]{8}(-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}$", id))]) &&
      can(regex("^[a-f0-9]{64}$", var.agent_orchestrator_authoring.draft_sha256)) &&
      try(var.agent_orchestrator_authoring.criterion_index >= 0 && floor(var.agent_orchestrator_authoring.criterion_index) == var.agent_orchestrator_authoring.criterion_index, false)
    )
    error_message = "Supply the published BA session UUID, run UUID, draft SHA-256 and zero-based criterion index. An external QA origin must use HTTPS."
  }
}

variable "agent_orchestrator_qa_api_key" {
  description = "QA shared API key for the Agent Orchestrator worker when using an explicitly configured QA API URL."
  type        = string
  sensitive   = true
  default     = null

  validation {
    condition     = var.agent_orchestrator_qa_api_key == null ? true : length(trimspace(var.agent_orchestrator_qa_api_key)) > 0
    error_message = "Supply a nonblank QA API key or leave it unset."
  }
}

variable "agent_orchestrator_github_read_token" {
  description = "Optional GitHub token for reading Storefront E2E Actions artifacts, contents and pull requests."
  type        = string
  sensitive   = true
  default     = null

  validation {
    condition     = var.agent_orchestrator_github_read_token == null ? true : length(trimspace(var.agent_orchestrator_github_read_token)) > 0
    error_message = "Supply a nonblank GitHub read token or leave it unset."
  }
}

variable "agent_orchestrator_langsmith_api_key" {
  description = "Optional LangSmith key for explicit Agent Orchestrator worker traces."
  type        = string
  sensitive   = true
  default     = null

  validation {
    condition     = var.agent_orchestrator_langsmith_api_key == null ? true : length(trimspace(var.agent_orchestrator_langsmith_api_key)) > 0
    error_message = "Supply a nonblank LangSmith key or leave it unset."
  }
}

locals {
  agent_orchestrator_api_env = var.agent_orchestrator_auth == null ? {} : {
    AO_AUTH_ISSUER   = var.agent_orchestrator_auth.issuer
    AO_AUTH_AUDIENCE = var.agent_orchestrator_auth.audience
    AO_AUTH_JWKS_URL = var.agent_orchestrator_auth.jwks_url
  }
  agent_orchestrator_mongodb_uri     = var.agent_orchestrator_mongodb_uri != null ? var.agent_orchestrator_mongodb_uri : local.users_connection_string
  agent_orchestrator_authoring       = var.agent_orchestrator_authoring != null
  agent_orchestrator_uses_managed_qa = try(var.agent_orchestrator_authoring.qa_api_url == null, false)
  agent_orchestrator_worker_qa_key   = local.agent_orchestrator_uses_managed_qa ? var.qa_api_key : var.agent_orchestrator_qa_api_key

  agent_orchestrator_worker_env = local.agent_orchestrator_authoring ? {
    AO_BA_API_URL = "http://${local.app_names.ba}"
    AO_QA_API_URL = local.agent_orchestrator_uses_managed_qa ? "http://${local.app_names.qa}" : var.agent_orchestrator_authoring.qa_api_url
    AO_SUPPORTED_HANDOFF = jsonencode({
      baSessionId    = var.agent_orchestrator_authoring.ba_session_id
      baRunId        = var.agent_orchestrator_authoring.ba_run_id
      draftSha256    = var.agent_orchestrator_authoring.draft_sha256
      criterionIndex = var.agent_orchestrator_authoring.criterion_index
    })
  } : {}
  agent_orchestrator_worker_secrets = merge({
    "ao-mongodb-uri" = local.agent_orchestrator_mongodb_uri
    }, local.agent_orchestrator_authoring ? {
    "ba-api-key" = var.ba_api_key
    "qa-api-key" = local.agent_orchestrator_worker_qa_key
    } : {}, var.agent_orchestrator_github_read_token != null ? {
    "github-read-token" = var.agent_orchestrator_github_read_token
    } : {}, var.agent_orchestrator_langsmith_api_key != null ? {
    "langsmith-api-key" = var.agent_orchestrator_langsmith_api_key
  } : {})
  agent_orchestrator_worker_secret_env = merge({
    AO_MONGODB_URI = "ao-mongodb-uri"
    }, local.agent_orchestrator_authoring ? {
    AO_BA_API_KEY = "ba-api-key"
    AO_QA_API_KEY = "qa-api-key"
    } : {}, var.agent_orchestrator_github_read_token != null ? {
    AO_GITHUB_READ_TOKEN = "github-read-token"
    } : {}, var.agent_orchestrator_langsmith_api_key != null ? {
    AO_LANGSMITH_API_KEY = "langsmith-api-key"
  } : {})
}

resource "azurerm_container_app" "agent_orchestrator_worker" {
  count = contains(keys(var.app_images), "agent_orchestrator_api") ? 1 : 0

  name                         = "ca-ecommercestore-ao-worker-dev"
  resource_group_name          = azurerm_resource_group.store.name
  container_app_environment_id = azurerm_container_app_environment.store.id
  workload_profile_name        = "Consumption"
  revision_mode                = "Single"
  tags                         = local.tags

  dynamic "secret" {
    for_each = merge(local.agent_orchestrator_worker_secrets, var.dockerhub_token == null ? {} : {
      "dockerhub-token" = var.dockerhub_token
    })
    content {
      name  = secret.key
      value = secret.value
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

  template {
    # The worker processes MongoDB claims independently of API traffic.
    min_replicas = 1
    max_replicas = 1

    container {
      name    = "agent-orchestrator-worker"
      image   = var.app_images.agent_orchestrator_api
      cpu     = 0.25
      memory  = "0.5Gi"
      command = ["python", "-m", "ecommerce_store_agent_orchestrator.worker"]

      dynamic "env" {
        for_each = local.agent_orchestrator_worker_env
        content {
          name  = env.key
          value = env.value
        }
      }

      dynamic "env" {
        for_each = local.agent_orchestrator_worker_secret_env
        content {
          name        = env.key
          secret_name = env.value
        }
      }
    }
  }

  depends_on = [azurerm_mongo_cluster_firewall_rule.azure]

  lifecycle {
    precondition {
      condition = !local.agent_orchestrator_authoring || (
        contains(keys(var.app_images), "ba") && var.ba_api_key != null &&
        (!local.agent_orchestrator_uses_managed_qa || contains(keys(var.app_images), "qa")) &&
        local.agent_orchestrator_worker_qa_key != null
      )
      error_message = "Orchestrator authoring requires the BA deployment and its API key plus either a managed QA deployment with its API key or an external QA URL and key."
    }
  }
}
