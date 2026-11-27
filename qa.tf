variable "qa_api_key" {
  description = "Shared server-side key for the managed QA API."
  type        = string
  sensitive   = true
  default     = null

  validation {
    condition     = var.qa_api_key == null ? true : length(trimspace(var.qa_api_key)) > 0
    error_message = "Supply a nonblank QA API key or leave the input unset."
  }
}

variable "qa_mongodb_uri" {
  description = "Optional QA MongoDB connection URI. Defaults to the shared DEV DocumentDB cluster."
  type        = string
  sensitive   = true
  default     = null

  validation {
    condition     = var.qa_mongodb_uri == null ? true : can(regex("^mongodb(\\+srv)?://[^[:space:]]+$", var.qa_mongodb_uri))
    error_message = "Supply a MongoDB connection URI for QA."
  }
}

variable "qa_e2e_github_token" {
  description = "GitHub token for QA to publish reviewed changes to the Storefront E2E repository."
  type        = string
  sensitive   = true
  default     = null

  validation {
    condition     = var.qa_e2e_github_token == null ? true : length(trimspace(var.qa_e2e_github_token)) > 0
    error_message = "Supply a nonblank GitHub token for QA or leave the input unset."
  }
}
