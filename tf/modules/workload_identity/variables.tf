variable "project_id" {
  type        = string
  description = "GCP project the service account lives in"
}

variable "account_id" {
  type        = string
  description = "Human-readable seed for the service account id (hashed/truncated to fit GCP's 30-char limit)"
}

variable "display_name" {
  type        = string
  description = "Display name for the created service account"
  default     = "Terraform-managed Flink workload service account"
}

variable "k8s_namespace" {
  type        = string
  description = "Namespace of the Kubernetes service account allowed to impersonate this GSA"
}

variable "k8s_service_account_name" {
  type        = string
  description = "Name of the Kubernetes service account allowed to impersonate this GSA"
  default     = "flink"
}

variable "bucket_roles" {
  type = list(object({
    bucket_name = string
    role        = string
  }))
  description = "Per-bucket IAM roles to grant the GSA, e.g. [{bucket_name = \"my-bucket\", role = \"roles/storage.objectAdmin\"}]"
  default     = []
}
