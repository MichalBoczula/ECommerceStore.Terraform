variable "payments_stripe_enabled" {
  description = "Allow Payments to create Stripe sandbox Checkout sessions. Disable to pause creation while keeping a configured webhook active."
  type        = bool
  default     = false
  nullable    = false

  validation {
    condition = !var.payments_stripe_enabled || (
      try(alltrue([for app in ["payments", "web"] : contains(keys(var.app_images), app)]), false) &&
      var.payments_stripe_secret_key != null && var.payments_stripe_webhook_secret != null
    )
    error_message = "Stripe test checkout requires the Payments and Web images, a Stripe test API key, and the deployed webhook's signing secret."
  }
}

variable "payments_stripe_checkout_vat_enabled" {
  description = "Include the Invoice service's sandbox VAT in new Stripe attempts. Enable after both Payments runtimes use a VAT-capable image."
  type        = bool
  default     = false
  nullable    = false
}

variable "payments_stripe_secret_key" {
  description = "Stripe sandbox sk_test_ API key for Payments checkout. Supply through TF_VAR_payments_stripe_secret_key."
  type        = string
  sensitive   = true
  default     = null

  validation {
    condition     = var.payments_stripe_secret_key == null || can(regex("^sk_test_\\S+$", var.payments_stripe_secret_key))
    error_message = "Supply an sk_test_ Stripe sandbox API key or leave the input unset."
  }
}

variable "payments_stripe_webhook_secret" {
  description = "Signing secret for the deployed Payments sandbox webhook. Supply through TF_VAR_payments_stripe_webhook_secret."
  type        = string
  sensitive   = true
  default     = null

  validation {
    condition     = var.payments_stripe_webhook_secret == null || can(regex("^whsec_\\S+$", var.payments_stripe_webhook_secret))
    error_message = "Supply a whsec_ Stripe webhook signing secret or leave the input unset."
  }

  validation {
    condition     = var.payments_stripe_webhook_secret == null || try(contains(keys(var.app_images), "payments"), false)
    error_message = "The Stripe webhook signing secret requires the Payments image."
  }
}
