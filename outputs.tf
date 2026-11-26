output "resource_group_name" {
  value = azurerm_resource_group.store.name
}

output "photo_storage_account_name" {
  value = azurerm_storage_account.photos.name
}

output "photos_base_url" {
  value = "${azurerm_storage_account.photos.primary_blob_endpoint}${azurerm_storage_container.photos.name}/"
}

output "invoice_storage_account_name" {
  value = azurerm_storage_account.photos.name
}

output "invoice_container_name" {
  value = azurerm_storage_container.invoices.name
}

output "livedocs_storage_account_name" {
  value = azurerm_storage_account.photos.name
}

output "livedocs_container_name" {
  value = azurerm_storage_container.livedocs.name
}

output "sql_server_name" {
  value = azurerm_mssql_server.products.name
}

output "sql_server_fqdn" {
  value = azurerm_mssql_server.products.fully_qualified_domain_name
}

output "documentdb_cluster_name" {
  value = azurerm_mongo_cluster.users.name
}

output "app_urls" {
  description = "Only apps enabled in app_images are listed."
  value       = { for name, app in azurerm_container_app.app : name => "https://${app.ingress[0].fqdn}" }
}

output "ba_principal_id" {
  description = "Grant this BA managed identity Azure AI User on the configured Foundry project."
  value       = try(azurerm_container_app.app["ba"].identity[0].principal_id, null)
}

output "agent_orchestrator_worker_name" {
  description = "Name of the ingress-free Agent Orchestrator worker when enabled."
  value       = one(azurerm_container_app.agent_orchestrator_worker[*].name)
}

output "mcp_url" {
  description = "Public Streamable HTTP endpoint when the catalog MCP server is enabled."
  value       = try("https://${azurerm_container_app.app["mcp"].ingress[0].fqdn}/mcp", null)
}

output "payments_fulfillment_job_name" {
  description = "The scheduled Payments fulfillment job, when enabled."
  value       = one(azurerm_container_app_job.payments_fulfillment[*].name)
}
