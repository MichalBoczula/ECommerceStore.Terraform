resource "azurerm_mongo_cluster" "users" {
  name                   = "doc-ecommercestore-dev-${var.name_suffix}"
  resource_group_name    = azurerm_resource_group.store.name
  location               = var.location
  administrator_username = "ecomoperator"
  administrator_password = var.mongo_admin_password
  compute_tier           = "Free"
  high_availability_mode = "Disabled"
  shard_count            = 1
  storage_size_in_gb     = 32
  version                = "8.0"
  public_network_access  = "Enabled"
  tags                   = local.tags
}

resource "azurerm_mongo_cluster_firewall_rule" "azure" {
  name             = "AllowAllAzureServicesAndResourcesWithinAzureIps"
  mongo_cluster_id = azurerm_mongo_cluster.users.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}
