terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "= 7.45.0"
    }
    kind = {
      source  = "tehcyx/kind"
      version = "= 0.11.0"
    }
  }
}

provider "google" {
  project = var.project_id != "" ? var.project_id : null
  region  = var.location != "" && var.location != "local" ? var.location : null
}

provider "kind" {}

# ka-smoke: bare cluster, no seeded workload. The kube-agents kanban smoke
# probe never touches cluster state, so this stack exists only to give the
# harness a live kubeconfig context to authenticate the credential proxy
# against (kube-agents' bootstrap always shells out to `gcloud container
# clusters get-credentials`). Copied from out/emitted/b-0034/stack/main.tf
# with the null_resource "setup" (and the seed manifests/setup.sh it ran)
# removed, since there is nothing for this task to seed.
module "cluster" {
  source          = "../../modules/cluster"
  infra_provider  = var.infra_provider
  project_id      = var.project_id
  cluster_name    = var.cluster_name
  location        = var.location
  node_count      = var.node_count
  machine_type    = var.machine_type
  kubeconfig_path = var.kubeconfig_path
}
