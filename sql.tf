resource "azurerm_mssql_server" "products" {
  name                          = "sql-ecommercestore-dev-${var.name_suffix}"
  resource_group_name           = azurerm_resource_group.store.name
  location                      = var.location
  version                       = "12.0"
  administrator_login           = "ecomoperator"
  administrator_login_password  = var.sql_admin_password
  minimum_tls_version           = "1.2"
  public_network_access_enabled = true
  tags                          = local.tags
}

resource "azapi_resource" "products_database" {
  type      = "Microsoft.Sql/servers/databases@2023-08-01"
  name      = "products"
  parent_id = azurerm_mssql_server.products.id
  location  = var.location
  tags      = local.tags

  body = {
    sku = {
      name     = "GP_S_Gen5"
      tier     = "GeneralPurpose"
      family   = "Gen5"
      capacity = 2
    }
    properties = {
      useFreeLimit                     = true
      freeLimitExhaustionBehavior      = "AutoPause"
      autoPauseDelay                   = 60
      minCapacity                      = 0.5
      maxSizeBytes                     = 34359738368
      requestedBackupStorageRedundancy = "Local"
      licenseType                      = "LicenseIncluded"
      zoneRedundant                    = false
    }
  }

  response_export_values = ["properties.useFreeLimit", "properties.freeLimitExhaustionBehavior"]

  lifecycle {
    postcondition {
      condition = (
        self.output.properties.useFreeLimit == true &&
        self.output.properties.freeLimitExhaustionBehavior == "AutoPause"
      )
      error_message = "Azure must confirm SQL Free with pause-at-limit enabled."
    }
  }
}

resource "azurerm_mssql_firewall_rule" "azure" {
  name             = "AllowAzureServices"
  server_id        = azurerm_mssql_server.products.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}

locals {
  # Quote the password to preserve semicolons and double quotes literally.
  products_connection_string = format(
    "Server=tcp:%s,1433;Database=products;User ID=ecomoperator;Password=\"%s\";Encrypt=True;TrustServerCertificate=False;Connection Timeout=60;",
    azurerm_mssql_server.products.fully_qualified_domain_name,
    replace(var.sql_admin_password, "\"", "\"\"")
  )
}
