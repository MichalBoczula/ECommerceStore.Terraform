locals {
  # The inventory is reference data for review and terraform console. Resources
  # still use var.app_images and the operator's private Terraform inputs.
  release_inventory = jsondecode(file("${path.module}/releases/portfolio.json"))
  release_profile_images = {
    for name, profile in local.release_inventory.profiles : name => {
      for app in profile.applications : app => local.release_inventory.applications[app].imageReference
    } if profile.status == "published"
  }
}
