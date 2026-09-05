terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "= 7.45.0"
    }
  }

  # GCS backend rather than local state: the bucket named below already
  # exists independently of this stack (it predates this task and is not
  # created or destroyed by any resource here), so there is no
  # bootstrapping cycle to solve. See README.md for why the per-attempt
  # checkpoint bucket this stack creates could NOT be used for its own
  # backend instead.
  backend "gcs" {
    bucket = "ehole-benchmark-temp-z8s8-f303-bf7670a0"
    prefix = "tf-state/layer0-smoke"
  }
}

provider "google" {
  project = var.project_id
  region  = var.location
}

locals {
  # Same "f303-<slug>" shape stream_runtime.py's namespace validation requires.
  namespace = "f303-${var.attempt_id}"

  # Preserves _ensure_bucket's naming shape (`<project>-f303-<12-char hash>`).
  # The original hashes `namespace:owner_id`; layer 0 is only given an
  # attempt_id, so the attempt_id stands in for that combined salt here.
  checkpoint_bucket_name = "${var.project_id}-f303-${substr(md5(var.attempt_id), 0, 12)}"
}

# --- 1. Adopt the existing cluster. No create path exists for it anywhere
# in this stack; see tf/modules/gke_cluster_data, which is data-source-only. ---
module "cluster" {
  source       = "../../modules/gke_cluster_data"
  project_id   = var.project_id
  location     = var.location
  cluster_name = var.cluster_name
}

# --- 2a. Per-attempt checkpoint/savepoint bucket. ---
module "checkpoint_bucket" {
  source                      = "../../modules/gcs_bucket"
  project_id                  = var.project_id
  location                    = var.location
  name                        = local.checkpoint_bucket_name
  uniform_bucket_level_access = true
  public_access_prevention    = true
  labels = {
    factory303-attempt = var.attempt_id
  }
}

# --- 2b. SQL runner jar bucket. Shared across attempts (see README), so the
# default path adopts it by data source; manage_jar_bucket=true is only for
# the one-time bootstrap (or hand-validating this module in isolation).
#
# allow_public_read is threaded through a variable, not hardcoded true: this
# project enforces the storage.publicAccessPrevention org policy (confirmed
# live, see README), so a public grant on this bucket fails apply here unless
# that policy is relaxed for this bucket. Leave jar_bucket_allow_public_read
# at its default until that is resolved; flip it once public read is actually
# obtainable in the target project. ---
module "jar_bucket" {
  source                      = "../../modules/gcs_bucket"
  count                       = var.manage_jar_bucket ? 1 : 0
  project_id                  = var.project_id
  location                    = var.location
  name                        = var.jar_bucket_name
  uniform_bucket_level_access = true
  allow_public_read           = var.jar_bucket_allow_public_read
  labels = {
    factory303-purpose = "sql-runner-jar"
  }
}

data "google_storage_bucket" "jar_bucket" {
  count = var.manage_jar_bucket ? 0 : 1
  name  = var.jar_bucket_name
}

locals {
  jar_bucket_name = var.manage_jar_bucket ? module.jar_bucket[0].bucket_name : data.google_storage_bucket.jar_bucket[0].name
}

# --- 3. GSA + WIF binding for the Kubernetes service account, with
# least-privilege, per-bucket IAM instead of a project-wide role. ---
module "workload_identity" {
  source                   = "../../modules/workload_identity"
  project_id               = var.project_id
  account_id               = "f303-flink-${var.attempt_id}"
  display_name             = "Flink workload identity for attempt ${var.attempt_id}"
  k8s_namespace            = local.namespace
  k8s_service_account_name = var.k8s_service_account_name
  bucket_roles = [
    { bucket_name = module.checkpoint_bucket.bucket_name, role = "roles/storage.objectAdmin" },
    { bucket_name = local.jar_bucket_name, role = "roles/storage.objectViewer" },
  ]
}
