terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "= 7.45.0"
    }
  }
}

# This module contains a single data source and no resources at all. That is
# a deliberate structural property, not a style choice: a stack that only
# ever imports this module has nothing here for `tofu apply` to create and
# nothing here for `tofu destroy` to delete. The cluster is adopted, never
# managed, so it is not possible for any composition of this module to
# destroy the cluster it looks up.
data "google_container_cluster" "this" {
  name     = var.cluster_name
  location = var.location
  project  = var.project_id
}
