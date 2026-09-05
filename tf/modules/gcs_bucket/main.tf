terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "= 7.45.0"
    }
  }
}

# Thin wrapper around the upstream cloud-storage module for a single named
# bucket, rather than hand-rolled google_storage_bucket. The upstream module
# is multi-bucket (a "names" list plus a "prefix"); passing prefix = "" and
# names = [var.name] makes it produce exactly var.name, so this wrapper's
# callers can pass a fully-formed bucket name (e.g. one already following an
# existing naming formula) without the module inserting anything extra.
module "bucket" {
  source  = "terraform-google-modules/cloud-storage/google"
  version = "12.3.0"

  project_id       = var.project_id
  location         = var.location
  names            = [var.name]
  prefix           = ""
  randomize_suffix = false
  labels           = var.labels

  bucket_policy_only = { (var.name) = var.uniform_bucket_level_access }
  force_destroy      = { (var.name) = var.force_destroy }

  # allow_public_read is an explicit, opt-in exception: it exists for the one
  # case (the SQL runner jar bucket) where a Flink operator's built-in
  # artifact fetcher needs to reach an object over plain https with no GCP
  # credentials at all. Public access prevention cannot be "enforced" on a
  # bucket that also carries a public IAM grant, so this wrapper flips it to
  # "inherited" only when the caller has explicitly asked for public read.
  public_access_prevention = var.allow_public_read ? "inherited" : (var.public_access_prevention ? "enforced" : "inherited")
}

resource "google_storage_bucket_iam_member" "public_read" {
  count  = var.allow_public_read ? 1 : 0
  bucket = module.bucket.name
  role   = "roles/storage.objectViewer"
  member = "allUsers"
}
