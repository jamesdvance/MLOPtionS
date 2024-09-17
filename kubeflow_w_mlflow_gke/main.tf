# Local variables
locals {
    project_id = "jamesdv-mlops"
    gcp_region = "us-central1"
    gke_version = "1.25"
    cluster_name = "kubeflow-mlops"
}

# Google Cloud
provider "google" {
    project = local.project_id
    region = local.gcp_region
}

# GKE Cluster 
resource "google_container_cluster" "primary" {
    name = local.cluster_name
    location = local.gcp_region

    remove_default_node_pool = true
    initial_node_count = 1 

    # GKE Version TODO - move to var
    min_master_version = local.gke_version

    # Workload Identity
    workload_identity_config {
       workload_pool = "${local.project_id}.svc.id.goog"
    }    
}




