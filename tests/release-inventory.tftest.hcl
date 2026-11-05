# Inventory checks are offline plans with no backend or Azure access.
mock_provider "azurerm" {}
mock_provider "azapi" {}

variables {
  subscription_id          = "00000000-0000-0000-0000-000000000001"
  sql_admin_password       = "Synthetic-Only-Sql-Password123!"
  mongo_admin_password     = "Synthetic-Only-Mongo-Password123!"
  app_images               = {}
  knowledge_search_enabled = false
}

run "inventory_tracks_every_supported_application" {
  command = plan

  assert {
    condition = (
      local.release_inventory.schemaVersion == 1 &&
      toset(keys(local.release_inventory.applications)) == toset(keys(local.app_config)) &&
      toset(keys(local.release_inventory.applications)) == toset(keys(local.app_names))
    )
    error_message = "The release inventory must contain one entry for every Terraform application."
  }

  assert {
    condition = alltrue([
      for app in values(local.release_inventory.applications) :
      can(regex("^docker\\.io/[a-z0-9._-]+/[a-z0-9._-]+@sha256:[a-f0-9]{64}$", app.imageReference)) &&
      can(regex("^[a-f0-9]{40}$", app.commitSha)) &&
      app.publication.runId > 0 && app.publication.runAttempt > 0 && app.publication.jobId > 0 &&
      app.publication.url == "https://github.com/${app.repository}/actions/runs/${app.publication.runId}"
    ])
    error_message = "Every release requires an immutable image, source commit and traceable CI publication."
  }

  assert {
    condition     = length(azurerm_container_app.app) == 0 && length(azurerm_search_service.knowledge) == 0
    error_message = "Adding a published release to the inventory must not opt in to deploying an app or Search."
  }
}

run "profiles_preserve_store_apps_and_require_real_rag_handoff" {
  command = plan

  assert {
    condition = alltrue([
      for profile in values(local.release_inventory.profiles) :
      length(profile.applications) == length(distinct(profile.applications)) &&
      length(setsubtract(toset(profile.applications), toset(keys(local.release_inventory.applications)))) == 0 &&
      length(setsubtract(toset(["products", "bff", "web", "users", "orders", "payments", "livedocs"]), toset(profile.applications))) == 0
    ])
    error_message = "Every profile must keep the seven store and LiveDocs apps and refer to known releases once each."
  }

  assert {
    condition = (
      toset(keys(local.release_profile_images["store-pact-search"])) == toset(keys(local.release_profile_images["store-pact"])) &&
      local.release_inventory.profiles["store-pact-search"].terraformSettings.knowledge_search_enabled &&
      !contains(keys(local.release_profile_images["store-pact-search"]), "knowledge_api") &&
      !contains(keys(local.release_profile_images["store-pact-search"]), "knowledge_web") &&
      contains(keys(local.release_profile_images["store-pact"]), "pact") &&
      contains(keys(local.release_profile_images["store-pact"]), "pact_web")
    )
    error_message = "Search bootstrap must preserve both Pact apps and work before the indexed Knowledge release exists."
  }

  assert {
    condition = (
      toset(keys(local.release_profile_images["full-demo"])) == toset(keys(local.app_config)) &&
      local.release_inventory.profiles["full-demo"].terraformSettings.knowledge_runtime_mode == "demo" &&
      local.release_inventory.applications.knowledge_api.contentMode == "synthetic-demo" &&
      !contains(keys(local.release_profile_images), "full-azure") &&
      local.release_inventory.profiles["full-azure"].requiredReleaseHandoff == "knowledge-refresh-handoff/release.json"
    )
    error_message = "The demo corpus must be labelled and no Azure RAG image map may be offered before the refresh handoff."
  }
}
