mock_provider "azurerm" {
  mock_resource "azurerm_container_app_environment" {
    override_during = plan
    defaults = {
      id             = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-ecommercestore-dev/providers/Microsoft.App/managedEnvironments/cae-ecommercestore-dev"
      default_domain = "synthetic.francecentral.azurecontainerapps.io"
    }
  }
  mock_resource "azurerm_mongo_cluster" {
    override_during = plan
    defaults = {
      id                 = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-ecommercestore-dev/providers/Microsoft.DocumentDB/mongoClusters/synthetic-mongo"
      connection_strings = [{ name = "synthetic", value = "mongodb+srv://synthetic:old-password@synthetic.mongocluster.cosmos.azure.com/?tls=true" }]
    }
  }
}
mock_provider "azapi" {}

variables {
  subscription_id      = "00000000-0000-0000-0000-000000000001"
  sql_admin_password   = "Synthetic-Only-Sql-Password123!"
  mongo_admin_password = "Synthetic-Only-Mongo-Password123!"
  app_images = {
    for app, release in jsondecode(file("releases/portfolio.json")).applications :
    app => release.imageReference
    if contains(["products", "users", "orders", "payments", "bff", "web"], app)
  }
}

run "stripe_is_off_by_default" {
  command = plan

  assert {
    condition = (
      tomap({ for env in azurerm_container_app.app["payments"].template[0].container[0].env :
        env.name => env.value if startswith(env.name, "PAYMENTS_STRIPE_")
      }) == tomap({ PAYMENTS_STRIPE_ENABLED = "false" }) &&
      toset([for secret in azurerm_container_app.app["payments"].secret : secret.name]) == toset(["database-connection"])
    )
    error_message = "The existing Pay/Get deployment must keep checkout off and require no Stripe secrets."
  }
}

run "stripe_checkout_uses_store_returns_and_payments_only_secret_references" {
  command = plan
  variables {
    payments_stripe_enabled              = true
    payments_stripe_checkout_vat_enabled = true
    payments_stripe_secret_key           = "sk_test_synthetic"
    payments_stripe_webhook_secret       = "whsec_synthetic"
  }

  assert {
    condition = tomap({
      for env in azurerm_container_app.app["payments"].template[0].container[0].env :
      env.name => { value = env.value, secret_name = env.secret_name }
      if startswith(env.name, "PAYMENTS_STRIPE_")
      }) == tomap({
      PAYMENTS_STRIPE_ENABLED              = { value = "true", secret_name = null }
      PAYMENTS_STRIPE_CHECKOUT_VAT_ENABLED = { value = "true", secret_name = null }
      PAYMENTS_STRIPE_SUCCESS_URL          = { value = "https://ca-ecommercestore-web-dev.synthetic.francecentral.azurecontainerapps.io/orders?checkout=success", secret_name = null }
      PAYMENTS_STRIPE_CANCEL_URL           = { value = "https://ca-ecommercestore-web-dev.synthetic.francecentral.azurecontainerapps.io/orders?checkout=cancel", secret_name = null }
      PAYMENTS_STRIPE_SECRET_KEY           = { value = null, secret_name = "stripe-api-key" }
      PAYMENTS_STRIPE_WEBHOOK_SECRET       = { value = null, secret_name = "stripe-webhook-secret" }
    })
    error_message = "Checkout must return to the deployed store and read both credentials from named secrets."
  }

  assert {
    condition = (
      toset([for secret in azurerm_container_app.app["payments"].secret : secret.name]) ==
      toset(["database-connection", "stripe-api-key", "stripe-webhook-secret"]) &&
      alltrue([for name, app in azurerm_container_app.app : alltrue([
        for secret in app.secret : !startswith(secret.name, "stripe-")
      ]) if name != "payments"])
    )
    error_message = "Both credentials belong only to the existing Payments app."
  }
}

run "stripe_webhook_can_receive_while_checkout_is_paused" {
  command = plan
  variables {
    payments_stripe_secret_key     = "sk_test_synthetic"
    payments_stripe_webhook_secret = "whsec_synthetic"
  }

  assert {
    condition = (
      tomap({ for env in azurerm_container_app.app["payments"].template[0].container[0].env :
        env.name => { value = env.value, secret_name = env.secret_name }
        if startswith(env.name, "PAYMENTS_STRIPE_")
        }) == tomap({
        PAYMENTS_STRIPE_ENABLED        = { value = "false", secret_name = null }
        PAYMENTS_STRIPE_WEBHOOK_SECRET = { value = null, secret_name = "stripe-webhook-secret" }
      }) &&
      toset([for secret in azurerm_container_app.app["payments"].secret : secret.name]) ==
      toset(["database-connection", "stripe-api-key", "stripe-webhook-secret"])
    )
    error_message = "Pausing must keep signed webhook delivery active and allow the API secret to be removed separately."
  }
}

run "stripe_checkout_requires_web" {
  command = plan
  variables {
    app_images = {
      for app, release in jsondecode(file("releases/portfolio.json")).applications :
      app => release.imageReference if contains(["products", "orders", "payments"], app)
    }
    payments_stripe_enabled        = true
    payments_stripe_secret_key     = "sk_test_synthetic"
    payments_stripe_webhook_secret = "whsec_synthetic"
  }
  expect_failures = [var.payments_stripe_enabled]
}

run "stripe_checkout_requires_both_credentials" {
  command = plan
  variables {
    payments_stripe_enabled    = true
    payments_stripe_secret_key = "sk_test_synthetic"
  }
  expect_failures = [var.payments_stripe_enabled]
}

run "stripe_rejects_live_api_key" {
  command = plan
  variables {
    payments_stripe_secret_key = "sk_live_synthetic"
  }
  expect_failures = [var.payments_stripe_secret_key]
}

run "stripe_rejects_malformed_signing_secret" {
  command = plan
  variables {
    payments_stripe_webhook_secret = "whsec_ "
  }
  expect_failures = [var.payments_stripe_webhook_secret]
}

run "stripe_webhook_requires_payments" {
  command = plan
  variables {
    app_images                     = {}
    payments_stripe_webhook_secret = "whsec_synthetic"
  }
  expect_failures = [var.payments_stripe_webhook_secret]
}
