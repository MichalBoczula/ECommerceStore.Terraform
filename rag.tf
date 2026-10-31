# The application owns index schemas, ingestion and content. Terraform owns capacity.
# Opt-in; Free capacity shortages fail deployment rather than selecting a paid tier.
resource "azurerm_search_service" "knowledge" {
  count = var.knowledge_search_enabled ? 1 : 0

  name                = "srch-ecommercestore-knowledge-${var.name_suffix}"
  resource_group_name = azurerm_resource_group.store.name
  location            = var.location
  sku                 = "free"
  tags                = local.tags
}

variable "knowledge_search_enabled" {
  description = "Opt in to the Free Search service. No paid SKU fallback or model resource creation."
  type        = bool
  default     = false
}

variable "knowledge_models" {
  description = "Existing Azure OpenAI v1 endpoint and deployed model names. Model calls are billed separately from Free Search."
  type = object({
    endpoint             = string
    chat_deployment      = string
    embedding_deployment = string
    embedding_dimensions = number
  })
  default = {
    endpoint             = ""
    chat_deployment      = ""
    embedding_deployment = ""
    embedding_dimensions = 1536
  }
  validation {
    condition     = var.knowledge_models.embedding_dimensions >= 1 && var.knowledge_models.embedding_dimensions <= 4096 && floor(var.knowledge_models.embedding_dimensions) == var.knowledge_models.embedding_dimensions
    error_message = "Embedding dimensions must be an integer from 1 to 4096 and match the deployed embedding model."
  }
}

variable "knowledge_openai_api_key" {
  description = "Key for the configured model resource; supplied through TF_VAR_knowledge_openai_api_key."
  type        = string
  sensitive   = true
  default     = null
}

variable "knowledge_api_key" {
  description = "Shared key between the Web server proxy and Python API. Never sent to the browser."
  type        = string
  sensitive   = true
  default     = null
  validation {
    condition     = var.knowledge_api_key == null ? true : can(regex("^[A-Za-z0-9_-]{32,128}$", var.knowledge_api_key))
    error_message = "Use a 32–128 character API key containing letters, numbers, underscore or hyphen."
  }
}

output "knowledge_search_endpoint" {
  description = "Null until Free Search is enabled."
  value       = try("https://${azurerm_search_service.knowledge[0].name}.search.windows.net", null)
}
