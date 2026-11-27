variable "mcp_checkout_auth" {
  description = "Enable MCP sandbox checkout with the tenant and API application IDs from the Entra v2 registration for MCP."
  type = object({
    tenant_id     = string
    api_client_id = string
  })
  default = null

  validation {
    condition = var.mcp_checkout_auth == null ? true : alltrue([
      for id in [var.mcp_checkout_auth.tenant_id, var.mcp_checkout_auth.api_client_id] :
      can(regex("^${local.entra_guid_pattern}$", lower(id)))
    ])
    error_message = "Supply the Microsoft Entra directory tenant ID and the MCP API application client ID as GUIDs."
  }
}

variable "mcp_checkout_identity_key" {
  description = "Stable secret used to map Entra users to storefront customers. Supply through TF_VAR_mcp_checkout_identity_key."
  type        = string
  sensitive   = true
  default     = null

  validation {
    condition     = var.mcp_checkout_identity_key == null ? true : length(trimspace(var.mcp_checkout_identity_key)) >= 32
    error_message = "Use a stable random MCP checkout identity key of at least 32 characters."
  }
}

locals {
  mcp_checkout_auth_env = var.mcp_checkout_auth == null ? {} : {
    ECOMMERCE_CHECKOUT_AUTH__TENANT_ID     = lower(var.mcp_checkout_auth.tenant_id)
    ECOMMERCE_CHECKOUT_AUTH__API_CLIENT_ID = lower(var.mcp_checkout_auth.api_client_id)
    ECOMMERCE_CHECKOUT_AUTH__RESOURCE_URL  = "${local.app_urls.mcp}/mcp"
  }
}
