variable "project_id" {
  type        = string
  description = "GCP project holding the pre-existing clusters and buckets"
  default     = "ehole-benchmark-temp-z8s8"
}

variable "location" {
  type        = string
  description = "Region the clusters live in"
  default     = "us-east1"
}

# Deliberately no default. A layer-0 stack that defaulted to any one cluster
# would make it easy to `tofu apply` against the wrong one by omission; the
# caller must name a cluster explicitly every time.
variable "cluster_name" {
  type        = string
  description = "Name of the pre-existing GKE cluster this attempt runs on (e.g. ehole-ap-use1-2). Never created or destroyed by this stack."
}

variable "attempt_id" {
  type        = string
  description = "Short, unique identifier for this attempt. Used to derive the owned namespace, the checkpoint bucket name, and the GSA name."

  validation {
    condition     = can(regex("^[a-z0-9](?:[a-z0-9-]{0,20}[a-z0-9])?$", var.attempt_id))
    error_message = "attempt_id must be lowercase alphanumeric/hyphen, at most 22 characters, matching the f303- namespace shape."
  }
}

variable "k8s_service_account_name" {
  type        = string
  description = "Name of the Kubernetes service account the Flink workload runs as"
  default     = "flink"
}

variable "jar_bucket_name" {
  type        = string
  description = "Name of the shared SQL runner jar bucket (see README: this bucket is shared across attempts, not per-attempt)"
  default     = "ehole-benchmark-temp-z8s8-f303-sql-runner-jars"
}

variable "manage_jar_bucket" {
  type        = bool
  description = "Create/destroy the shared jar bucket from this stack. Only true for the one-time bootstrap of the shared bucket (or, as here, for hand-validating the module); every normal per-attempt run should leave this false and adopt the already-existing shared bucket."
  default     = false
}

variable "jar_bucket_allow_public_read" {
  type        = bool
  description = "Grant allUsers read on the jar bucket (only meaningful when manage_jar_bucket=true). Defaults to true because the Flink operator's built-in artifact fetcher needs anonymous https access, but this fails apply in any project that enforces the storage.publicAccessPrevention org policy, as ehole-benchmark-temp-z8s8 currently does; see README.md."
  default     = true
}
