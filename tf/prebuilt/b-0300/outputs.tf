# b-0300 -- cluster outputs.
#
# The harness reads these cluster identity outputs back out of `tofu output
# -json` and raises ConfigError if either is missing. Do not rename them.
output "cluster_name" {
  value       = module.cluster.cluster_name
  description = "The finalized name of the created cluster"
}

output "cluster_location" {
  value       = module.cluster.location
  description = "The region/zone or 'local'"
}

# VClusterProvider consumes the raw, sensitive kubeconfig after apply and
# writes it into the run-isolated path supplied as kubeconfig_path.
output "kubeconfig" {
  value       = module.cluster.kubeconfig
  description = "Raw kubeconfig YAML for the provisioned virtual cluster"
  sensitive   = true
}
