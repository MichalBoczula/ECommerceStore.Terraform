# Opt-in app entry in the existing root/state; no second ACA environment or database cluster.
variable "pact_publishers" {
  description = "Publisher IDs mapped to explicit application scopes. Pact is enabled by adding app_images.pact. Wildcard scopes are not accepted for this hosted registry."
  type        = map(set(string))
  default     = {}
  nullable    = false
  validation {
    condition = length(var.pact_publishers) <= 10 && alltrue([
      for publisher, applications in var.pact_publishers :
      length(publisher) <= 100 && can(regex("^[a-z0-9]+(-[a-z0-9]+)*$", publisher)) &&
      (applications == null ? false : length(applications) >= 1 && length(applications) <= 20 && alltrue([
        for application in applications : can(regex("^[a-z0-9]+(-[a-z0-9]+)*$", application)) && try(length(application) <= 100, false)
      ]))
    ])
    error_message = "Use at most 10 lowercase publisher IDs with 1-20 explicit valid application IDs each; no wildcard scopes."
  }
}

variable "pact_publisher_token_sha256" {
  description = "Distinct SHA-256 hashes of source CI bearer tokens, supplied through TF_VAR_pact_publisher_token_sha256. Raw bearer tokens remain in source CI secrets."
  type        = map(string)
  sensitive   = true
  default     = {}
  nullable    = false
  validation {
    condition = (alltrue([for hash in values(var.pact_publisher_token_sha256) : can(regex("^[a-fA-F0-9]{64}$", hash))]) &&
    length(distinct([for hash in values(var.pact_publisher_token_sha256) : try(lower(hash), "")])) == length(var.pact_publisher_token_sha256))
    error_message = "Publisher token hashes must be distinct 64-character hexadecimal SHA-256 values."
  }
}

variable "pact_mongo_database_name" {
  description = "Dedicated database namespace on the existing MongoDB-compatible cluster."
  type        = string
  default     = "ecommerce-store-pact-db"
  validation {
    condition = (length(var.pact_mongo_database_name) >= 1 && length(var.pact_mongo_database_name) <= 63 &&
      can(regex("^[a-zA-Z0-9_-]+$", var.pact_mongo_database_name)) &&
    !contains(["admin", "config", "local", "ecommerce-store-users-db", "ecommerce-store-invoice-db", "ecommerce-store-payments-db"], lower(var.pact_mongo_database_name)))
    error_message = "Use a dedicated 1-63 character database name, separate from system and existing service databases."
  }
}

variable "pact_mongo_timeout_seconds" {
  description = "Bounded connection/readiness timeout for the registry's MongoDB driver."
  type        = number
  default     = 3
  validation {
    condition     = var.pact_mongo_timeout_seconds >= 1 && var.pact_mongo_timeout_seconds <= 30 && floor(var.pact_mongo_timeout_seconds) == var.pact_mongo_timeout_seconds
    error_message = "Pact Mongo timeout must be an integer from 1 to 30 seconds."
  }
}

variable "pact_ingress_external" {
  description = "Public HTTPS is needed for GitHub-hosted CI. Disable only when callers have access inside this ACA environment. Writes always require scoped publisher tokens."
  type        = bool
  default     = true
}

variable "pact_allowed_ingress_cidrs" {
  description = "Optional stable IPv4 CIDR allowlist for Pact ingress, e.g. a self-hosted runner's egress. Empty permits public reads and token-authenticated writes when external ingress is enabled."
  type        = set(string)
  default     = []
  validation {
    condition     = alltrue([for cidr in var.pact_allowed_ingress_cidrs : can(cidrnetmask(cidr))])
    error_message = "Pact ingress restrictions must use valid IPv4 CIDR ranges."
  }
}
