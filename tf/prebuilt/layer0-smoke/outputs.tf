output "cluster_name" {
  value       = module.cluster.cluster_name
  description = "The adopted cluster's name"
}

output "cluster_endpoint" {
  value       = module.cluster.endpoint
  description = "The adopted cluster's control plane endpoint"
}

output "cluster_ca_certificate" {
  value       = module.cluster.cluster_ca_certificate
  description = "The adopted cluster's CA certificate, for the kubernetes/helm providers"
  sensitive   = true
}

output "workload_identity_pool" {
  value       = module.cluster.workload_identity_pool
  description = "Workload Identity pool for this project"
}

output "namespace" {
  value       = local.namespace
  description = "The owned namespace this attempt's Flink workload runs in"
}

output "checkpoint_bucket_name" {
  value       = module.checkpoint_bucket.bucket_name
  description = "Per-attempt checkpoint/savepoint bucket"
}

output "checkpoint_bucket_url" {
  value = module.checkpoint_bucket.bucket_url
}

output "jar_bucket_name" {
  value       = local.jar_bucket_name
  description = "Shared SQL runner jar bucket (adopted unless manage_jar_bucket=true)"
}

output "gsa_email" {
  value       = module.workload_identity.gsa_email
  description = "GSA the Flink workload assumes via Workload Identity"
}

output "k8s_service_account_annotation" {
  value       = module.workload_identity.k8s_service_account_annotation
  description = "Annotation to apply to the flink KSA so it can impersonate the GSA"
}
