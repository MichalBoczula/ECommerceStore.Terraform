variable "ba_runtime" {
  description = "Runtime configuration for the optional Business Analyst API. Set when app_images.ba is supplied."
  type = object({
    foundry_project_endpoint = string
    foundry_agent_version    = string
    foundry_agent_name       = optional(string, "ecommerce-business-analyst")
    jira_site_url            = string
    jira_api_url             = optional(string)
    jira_email               = string
    jira_project_key         = string
    jira_issue_type_id       = string
  })
  default = null

  validation {
    condition = var.ba_runtime == null ? true : (
      can(regex("^https://[a-z0-9-]+\\.services\\.ai\\.azure\\.com/api/projects/[A-Za-z0-9_-]+/?$", var.ba_runtime.foundry_project_endpoint)) &&
      can(regex("^[A-Za-z0-9][A-Za-z0-9_-]{0,62}$", var.ba_runtime.foundry_agent_name)) &&
      try(length(trimspace(var.ba_runtime.foundry_agent_version)) > 0, false) &&
      can(regex("^https://[a-z0-9.-]+/?$", var.ba_runtime.jira_site_url)) &&
      (var.ba_runtime.jira_api_url == null ? true : can(regex("^https://api\\.atlassian\\.com/ex/jira/[a-zA-Z0-9-]+/?$", var.ba_runtime.jira_api_url))) &&
      try(length(trimspace(var.ba_runtime.jira_email)) > 0, false) &&
      can(regex("^[A-Z][A-Z0-9_]*$", var.ba_runtime.jira_project_key)) &&
      can(regex("^[0-9]+$", var.ba_runtime.jira_issue_type_id))
    )
    error_message = "BA requires a Foundry project URL and agent version plus a valid Jira Cloud site, identity, project and issue type."
  }
}

variable "ba_api_key" {
  description = "Shared server-side key for authenticated BA clients."
  type        = string
  sensitive   = true
  default     = null

  validation {
    condition     = var.ba_api_key == null ? true : can(regex("^[A-Za-z0-9_-]{32,128}$", var.ba_api_key))
    error_message = "Use a random BA API key of 32 to 128 URL-safe characters."
  }
}

variable "ba_mongodb_uri" {
  description = "MongoDB connection string with read and write access to the ecommerce_store_ba database."
  type        = string
  sensitive   = true
  default     = null

  validation {
    condition     = var.ba_mongodb_uri == null ? true : can(regex("^mongodb(\\+srv)?://[^[:space:]]+$", var.ba_mongodb_uri))
    error_message = "Supply a MongoDB connection URI for BA."
  }
}

variable "ba_jira_api_token" {
  description = "API token for the Jira Cloud identity used by BA."
  type        = string
  sensitive   = true
  default     = null

  validation {
    condition     = var.ba_jira_api_token == null ? true : try(length(trimspace(var.ba_jira_api_token)) > 0, false)
    error_message = "Supply a nonblank Jira API token for BA."
  }
}

locals {
  ba_env = var.ba_runtime == null ? {} : merge({
    BA_KNOWLEDGE_API_URL        = "http://${local.app_names.knowledge_api}"
    BA_FOUNDRY_PROJECT_ENDPOINT = var.ba_runtime.foundry_project_endpoint
    BA_FOUNDRY_AGENT_NAME       = var.ba_runtime.foundry_agent_name
    BA_FOUNDRY_AGENT_VERSION    = var.ba_runtime.foundry_agent_version
    BA_JIRA_SITE_URL            = var.ba_runtime.jira_site_url
    BA_JIRA_EMAIL               = var.ba_runtime.jira_email
    BA_JIRA_PROJECT_KEY         = var.ba_runtime.jira_project_key
    BA_JIRA_ISSUE_TYPE_ID       = var.ba_runtime.jira_issue_type_id
    }, var.ba_runtime.jira_api_url == null ? {} : {
    BA_JIRA_API_URL = var.ba_runtime.jira_api_url
  })
}
