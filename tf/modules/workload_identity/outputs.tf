output "gsa_email" {
  value       = module.gsa.email
  description = "Email of the created Google service account"
}

output "gsa_member" {
  value       = "serviceAccount:${module.gsa.email}"
  description = "IAM-format member string for the created service account"
}

output "k8s_service_account_annotation" {
  value       = { "iam.gke.io/gcp-service-account" = module.gsa.email }
  description = "Annotation map to apply to the Kubernetes service account named in k8s_service_account_name"
}
