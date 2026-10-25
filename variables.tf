variable "subscription_id" {
  description = "Azure subscription that will contain the store."
  type        = string
}

variable "location" {
  description = "One region for the store. Keep France Central if this subscription's SQL Free offer is tied to it."
  type        = string
  default     = "francecentral"
}

variable "name_suffix" {
  description = "Stable suffix for globally unique SQL and DocumentDB names."
  type        = string
  default     = "mb261024"
}

variable "photo_storage_account_name" {
  description = "Matches the hostname already embedded in Products seed migrations. Must be free to create, or imported first."
  type        = string
  default     = "stecproductsdevmb261013"
}

variable "sql_admin_password" {
  description = "SQL password for this disposable educational environment. Reuse the same value on later plans."
  type        = string
  sensitive   = true
}

variable "mongo_admin_password" {
  description = "DocumentDB password. Reuse the same value on later plans."
  type        = string
  sensitive   = true
}

variable "app_images" {
  description = "Apps to deploy, keyed by products, bff, web, users, orders, payments or livedocs. Empty creates only the foundation. Keep existing entries when adding another service."
  type        = map(string)
  default     = {}

  validation {
    condition = alltrue([
      for name, image in var.app_images :
      contains(["products", "bff", "web", "users", "orders", "payments", "livedocs"], name) && length(trimspace(image)) > 0
    ])
    error_message = "Use only products, bff, web, users, orders, payments and livedocs keys with non-empty image references."
  }
}

variable "dockerhub_username" {
  description = "Docker Hub username for authenticated image pulls."
  type        = string
  default     = "mb0101"
}

variable "dockerhub_token" {
  description = "Optional read-only Docker Hub token for authenticated image pulls. Public images work without it."
  type        = string
  sensitive   = true
  default     = null
}
