variable "project_id" {
  type        = string
  description = "GCP project the cluster lives in"
}

variable "location" {
  type        = string
  description = "Region or zone the cluster was created in"
}

variable "cluster_name" {
  type        = string
  description = "Name of the pre-existing GKE cluster to adopt"
}
