# Use the existing account; invoice PDFs are read through the application API.
resource "azurerm_storage_container" "invoices" {
  name                  = "invoices"
  storage_account_id    = azurerm_storage_account.photos.id
  container_access_type = "private"
}
