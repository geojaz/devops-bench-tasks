output "cluster_name" {
  value       = data.google_container_cluster.this.name
  description = "Name of the adopted cluster"
}

output "location" {
  value       = data.google_container_cluster.this.location
  description = "Region or zone of the adopted cluster"
}

output "endpoint" {
  value       = data.google_container_cluster.this.endpoint
  description = "Cluster control plane endpoint, for the kubernetes/helm providers"
}

output "cluster_ca_certificate" {
  value       = base64decode(data.google_container_cluster.this.master_auth[0].cluster_ca_certificate)
  description = "Decoded cluster CA certificate, for the kubernetes/helm providers"
  sensitive   = true
}

output "self_link" {
  value       = data.google_container_cluster.this.self_link
  description = "Fully qualified self link of the adopted cluster"
}

output "workload_identity_pool" {
  value       = "${var.project_id}.svc.id.goog"
  description = "The Workload Identity pool for this project, used to bind a Kubernetes service account to a Google service account"
}
