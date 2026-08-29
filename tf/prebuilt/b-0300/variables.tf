variable "infra_provider" {
  type        = string
  description = "The target infrastructure provider (gcp, kind, vcluster)"
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
  description = "Enable autoscaling on the task-owned GKE node pool"
  default     = true
}

variable "min_node_count" {
  type        = number
  description = "Minimum size of the task-owned GKE node pool"
  default     = 1
}

variable "max_node_count" {
  type        = number
  description = "Maximum size of the task-owned GKE node pool"
  default     = 1
}
variable "create_host_node_pool" {
  type        = bool
  description = "Create an attempt-scoped node pool on the standing vcluster host"
  default     = true
}

# Provider-specific optional variables
variable "project_id" {
  type        = string
  description = "GCP Project ID"
  default     = ""
}

variable "kubeconfig_path" {
  type        = string
  description = "Target path to write kubeconfig (KinD-only)"
  default     = "~/.kube/config"
}
variable "host_kubecontext" {
  type        = string
  description = "Standing host Kubernetes context (vcluster-only)"
  default     = null
}

variable "host_kubeconfig_path" {
  type        = string
  description = "Standing host kubeconfig path (vcluster-only)"
  default     = "~/.kube/config"
}

variable "service_type" {
  type        = string
  description = "Virtual-cluster API Service exposure type"
  default     = "LoadBalancer"
}

variable "service_cidr" {
  type        = string
  description = "Standing host Service CIDR forwarded to vcluster"
  default     = ""
}

variable "host_project_id" {
  type        = string
  description = "Project containing the standing GKE host"
  default     = ""
}

variable "host_cluster_name" {
  type        = string
  description = "Standing GKE host cluster name"
  default     = ""
}

variable "host_cluster_location" {
  type        = string
  description = "Standing GKE host region or zone"
  default     = ""
}

variable "host_node_pool_name" {
  type        = string
  description = "Attempt-scoped node-pool name"
  default     = ""
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
