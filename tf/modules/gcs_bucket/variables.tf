variable "project_id" {
  type        = string
  description = "GCP project to create the bucket in"
}

variable "name" {
  type        = string
  description = "Fully-formed bucket name (no prefix is applied by this module)"
}

variable "location" {
  type        = string
  description = "Bucket location"
  default     = "us-east1"
}

variable "uniform_bucket_level_access" {
  type        = bool
  description = "Disable ad-hoc object ACLs in favor of IAM-only access"
  default     = true
}

variable "public_access_prevention" {
  type        = bool
  description = "Enforce GCS public access prevention. Forced off when allow_public_read is true."
  default     = true
}

variable "allow_public_read" {
  type        = bool
  description = "Grant roles/storage.objectViewer to allUsers on this bucket. Only intended for a bucket that must be readable over anonymous https, never for the per-attempt checkpoint bucket."
  default     = false
}

variable "force_destroy" {
  type        = bool
  description = "Allow tofu destroy to delete a non-empty bucket"
  default     = false
}

variable "labels" {
  type        = map(string)
  description = "Labels applied to the bucket"
  default     = {}
}
