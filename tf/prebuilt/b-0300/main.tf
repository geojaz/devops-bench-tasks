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
    null = {
      source  = "hashicorp/null"
      version = "= 3.3.1"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.25"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
    local = {
      source  = "hashicorp/local"
      version = ">= 2.0"
    }
  }
}

provider "google" {
  project = var.project_id != "" ? var.project_id : null
  region  = var.location != "" && var.location != "local" ? var.location : null
}

provider "kind" {}

provider "kubernetes" {
  config_path    = var.infra_provider == "vcluster" ? pathexpand(var.host_kubeconfig_path) : null
  config_context = var.infra_provider == "vcluster" ? var.host_kubecontext : null
}

provider "helm" {
  kubernetes {
    config_path    = var.infra_provider == "vcluster" ? pathexpand(var.host_kubeconfig_path) : null
    config_context = var.infra_provider == "vcluster" ? var.host_kubecontext : null
  }
}

# b-0300: The missing ordinal. The seed manifests
# (manifests/00-gating.yaml, manifests/10-workloads.yaml) and the workload
# they seed are applied by setup.sh.
module "cluster" {
  source                     = "../../modules/cluster"
  infra_provider             = var.infra_provider
  project_id                 = var.project_id
  cluster_name               = var.cluster_name
  location                   = var.location
  node_count                 = var.node_count
  machine_type               = var.machine_type
  enable_autoscaling         = var.enable_autoscaling
  min_node_count             = var.min_node_count
  max_node_count             = var.max_node_count
  kubeconfig_path            = var.kubeconfig_path
  host_kubeconfig_path       = var.host_kubeconfig_path
  host_kubecontext           = var.host_kubecontext
  service_type               = var.service_type
  vcluster_service_cidr      = var.service_cidr
  create_host_node_pool      = var.create_host_node_pool
  host_project_id            = var.host_project_id
  host_cluster_name          = var.host_cluster_name
  host_cluster_location      = var.host_cluster_location
  host_node_pool_name        = var.host_node_pool_name
}

resource "local_sensitive_file" "vcluster_kubeconfig" {
  count    = var.infra_provider == "vcluster" ? 1 : 0
  content  = module.cluster.kubeconfig
  filename = pathexpand(var.kubeconfig_path)
  file_permission = "0600"
}

# Outside-the-cluster setup for b-0300: apply the seed manifests in
# gating-then-rest order (see manifests/00-gating.yaml, manifests/10-workloads.yaml)
# and assert the seeded condition(s) actually hold before the agent starts. Runs
# during `tofu apply`, before the agent starts.
resource "null_resource" "setup" {
  depends_on = [module.cluster, local_sensitive_file.vcluster_kubeconfig]

  triggers = {
    cluster = module.cluster.cluster_name
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = "${path.module}/scripts/setup.sh"
    environment = {
      INFRA_PROVIDER = var.infra_provider
      PROJECT_ID     = var.project_id
      GCP_PROJECT_ID = var.infra_provider == "vcluster" ? var.host_project_id : var.project_id
      CLUSTER_NAME   = module.cluster.cluster_name
      HOST_CLUSTER_NAME     = var.host_cluster_name
      HOST_CLUSTER_LOCATION = var.host_cluster_location
      LOCATION       = var.location
      KUBECONFIG     = var.infra_provider == "vcluster" ? local_sensitive_file.vcluster_kubeconfig[0].filename : pathexpand(var.kubeconfig_path)
      MANIFESTS_DIR  = "${path.module}/manifests"
      WAIT_TIMEOUT   = var.wait_timeout
    }
  }
}
