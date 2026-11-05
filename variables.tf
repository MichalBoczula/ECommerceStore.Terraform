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
  nullable    = false

  validation {
    condition     = length(trimspace(var.sql_admin_password)) > 0
    error_message = "Supply a nonblank SQL administrator password."
  }
}

variable "mongo_admin_password" {
  description = "DocumentDB password. Reuse the same value on later plans."
  type        = string
  sensitive   = true
  nullable    = false

  validation {
    condition     = length(trimspace(var.mongo_admin_password)) > 0
    error_message = "Supply a nonblank DocumentDB administrator password."
  }
}

variable "app_images" {
  description = "Apps to deploy, keyed by products, bff, web, users, orders, payments, livedocs, knowledge_api, knowledge_web, pact or pact_web. Empty creates only the foundation. Keep existing entries when adding another service."
  type        = map(string)
  default     = {}

  validation {
    condition     = var.app_images == null ? false : length(setsubtract(toset(keys(var.app_images)), toset(keys(local.app_names)))) == 0
    error_message = "Supply an app_images map with supported keys (${join(", ", keys(local.app_names))})."
  }

  validation {
    condition = var.app_images == null ? true : alltrue([
      for image in values(var.app_images) : can(regex("^docker\\.io/[a-z0-9._-]+/[a-z0-9._-]+@sha256:[a-f0-9]{64}$", image))
    ])
    error_message = "Pin each app_images entry to an immutable docker.io/namespace/repository@sha256 digest with 64 lowercase hexadecimal characters."
  }
}

variable "dockerhub_username" {
  description = "Docker Hub username for authenticated image pulls."
  type        = string
  default     = "mb0101"
  nullable    = false

  validation {
    condition     = var.dockerhub_token == null || length(trimspace(var.dockerhub_username)) > 0
    error_message = "Supply a Docker Hub username when configuring an authenticated pull token."
  }
}

variable "dockerhub_token" {
  description = "Optional read-only Docker Hub token for authenticated image pulls. Public images work without it."
  type        = string
  sensitive   = true
  default     = null

  validation {
    condition     = var.dockerhub_token == null ? true : length(trimspace(var.dockerhub_token)) > 0
    error_message = "Supply a nonblank Docker Hub pull token or leave the input unset."
  }
}

