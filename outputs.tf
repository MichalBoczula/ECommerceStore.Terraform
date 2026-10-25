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
