# CI archives source bundles here, then bakes generated Allure pages into an image.
# Keep the archive independent of whether the optional LiveDocs ACA is enabled.
resource "azurerm_storage_container" "livedocs" {
  name                  = "livedocs"
  storage_account_id    = azurerm_storage_account.photos.id
  container_access_type = "private"
}
