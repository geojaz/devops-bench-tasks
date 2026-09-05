terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "= 7.45.0"
    }
  }
}

# A GCP IAM account_id must be <= 30 chars of lowercase letters, digits, and
# hyphens. Truncating the readable name alone risks collisions between two
# attempt ids that share a long prefix, so keep a slug of the name plus a
# short hash of the *full* name, the same shape tf/modules/cluster/gke/main.tf
# already uses for its node service account.
locals {
  account_slug       = trim(substr(replace(lower(var.account_id), "/[^a-z0-9-]+/", "-"), 0, 22), "-")
  service_account_id = "${local.account_slug}-${substr(md5(var.account_id), 0, 6)}"
  bucket_bindings    = { for entry in var.bucket_roles : "${entry.bucket_name}:${entry.role}" => entry }
}

module "gsa" {
  source  = "terraform-google-modules/service-accounts/google"
  version = "4.7.0"

  project_id    = var.project_id
  names         = [local.service_account_id]
  display_name  = var.display_name
  project_roles = [] # No project-wide roles. Access is granted per-bucket below.
}

# Least privilege, scoped to exactly the buckets this workload needs, never
# to the project. Replaces the imperative `_bind_bucket` grant.
resource "google_storage_bucket_iam_member" "bucket_access" {
  for_each = local.bucket_bindings
  bucket   = each.value.bucket_name
  role     = each.value.role
  member   = "serviceAccount:${module.gsa.email}"
}

# Lets the Kubernetes service account impersonate the GSA via GKE Workload
# Identity Federation, replacing the imperative `_bind_bucket` principal wiring.
resource "google_service_account_iam_member" "workload_identity_user" {
  service_account_id = module.gsa.service_account.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[${var.k8s_namespace}/${var.k8s_service_account_name}]"
}
