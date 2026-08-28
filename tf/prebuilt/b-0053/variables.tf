variable "infra_provider" {
  type        = string
  description = "The target cloud provider (gcp, kind)"
}

variable "cluster_name" {
  type        = string
  description = "Name of the cluster to provision"
}

variable "location" {
  type        = string
  description = "Region/zone (GCP) or 'local' (KinD)"
  default     = ""
}

variable "node_count" {
  type        = number
  description = "Number of nodes (1 control-plane + worker nodes)"
  default     = 1
}

variable "machine_type" {
  type        = string
  description = "VM instance type"
  default     = "e2-standard-2"
}

variable "enable_autoscaling" {
  type        = bool
  description = "Enable autoscaling on the primary GKE node pool"
  default     = true
}

variable "min_node_count" {
  type        = number
  description = "Minimum nodes per zone when GKE node-pool autoscaling is enabled"
  default     = 1
}

variable "max_node_count" {
  type        = number
  description = "Maximum nodes per zone when GKE node-pool autoscaling is enabled"
  default     = 1
}

# Provider-specific optional variables
variable "project_id" {
  type        = string
  description = "GCP Project ID"
  default     = ""
}

variable "kubeconfig_path" {
  type        = string
  description = "Run-scoped target path where the provider writes kubeconfig"
  default     = "~/.kube/config"
}

variable "wait_timeout" {
  type        = string
  description = "Seconds each bounded poll in setup.sh will wait before declaring SEED FAIL."
  default     = "180"
}

# Unused by this bare stack, but declared so tasks that pin NAMESPACE (for
# prompt/fixture consistency) don't trip an "undeclared variable" warning when
# the provider resolver forwards namespace= to every GCP stack.
variable "namespace" {
  type    = string
  default = "default"
}
