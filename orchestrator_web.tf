variable "agent_orchestrator_web_entra_client_id" {
  description = "Optional client ID of the Entra SPA registration for Agent Orchestrator Web."
  type        = string
  default     = null

  validation {
    condition     = var.agent_orchestrator_web_entra_client_id == null ? true : can(regex("^${local.entra_guid_pattern}$", lower(var.agent_orchestrator_web_entra_client_id)))
    error_message = "Supply the Entra SPA application client ID as a GUID."
  }

  validation {
    condition = var.agent_orchestrator_web_entra_client_id == null ? true : (
      local.agent_orchestrator_entra_tenant_id != null &&
      can(regex("^${local.entra_guid_pattern}$", var.agent_orchestrator_auth.audience))
    )
    error_message = "Orchestrator Web Entra sign-in requires the tenant-specific Microsoft Entra v2 issuer and API application ID as the audience."
  }
}

locals {
  entra_guid_pattern = "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}"

  agent_orchestrator_entra_tenant_id = try(
    regex("^https://login\\.microsoftonline\\.com/(${local.entra_guid_pattern})/v2\\.0$", var.agent_orchestrator_auth.issuer)[0],
    null,
  )

  agent_orchestrator_web_entra_env = var.agent_orchestrator_web_entra_client_id == null ? {} : {
    AO_ENTRA_TENANT_ID     = local.agent_orchestrator_entra_tenant_id
    AO_ENTRA_CLIENT_ID     = lower(var.agent_orchestrator_web_entra_client_id)
    AO_ENTRA_API_CLIENT_ID = try(var.agent_orchestrator_auth.audience, null)
  }
}
