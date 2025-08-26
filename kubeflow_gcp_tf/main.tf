# Local variables
locals {
    config  = yamldecode(file("${path.module}/config.yaml"))
}

# Google Cloud
provider "google" {
    project = local.config.project_id
    region = local.config.gcp_region
}

# Network for Kubeflow
resource "google_compute_network" "kubeflow_network" {
    name = "${local.config.cluster_name}-network"
    auto_create_subnetworks = false
}

# Subnet for Kubeflow
resource "google_compute_subnetwork" "kubeflow_subnet" {
    name = "${local.config.cluster_name}-subnet"
    ip_cidr_range = "10.0.0.0/16"
    region = local.config.gcp_region
    network = google_compute_network.kubeflow_network.self_link

    secondary_ip_range {
        range_name = "pods"
        ip_cidr_range = "10.1.0.0/16"
    }

    secondary_ip_range {
        range_name = "services"
        ip_cidr_range = "10.2.0.0/16"
    }
}

# GKE Cluster 
resource "google_container_cluster" "primary" {
    name = local.config.cluster_name
    location = local.config.gcp_region

    remove_default_node_pool = true
    initial_node_count = 1 
    deletion_protection = false

    # GKE Version
    min_master_version = local.config.gke_version

    # Workload Identity
    workload_identity_config {
       workload_pool = "${local.config.project_id}.svc.id.goog"
    }

    # Network configuration for Kubeflow
    network = google_compute_network.kubeflow_network.self_link
    subnetwork = google_compute_subnetwork.kubeflow_subnet.self_link

    # IP allocation for pods and services
    ip_allocation_policy {
        cluster_secondary_range_name = "pods"
        services_secondary_range_name = "services"
    }

    # Enable network policy
    network_policy {
        enabled = true
    }

    # Addons
    addons_config {
        network_policy_config {
            disabled = false
        }
    }
}

# Service Account for Kubeflow nodes
resource "google_service_account" "kubeflow_node_sa" {
    account_id = "${local.config.cluster_name}-node-sa"
    display_name = "Kubeflow Node Service Account"
}

resource "google_project_iam_member" "kubeflow_node_sa_roles" {
    for_each = toset([
        "roles/logging.logWriter",
        "roles/monitoring.metricWriter",
        "roles/monitoring.viewer",
        "roles/storage.objectViewer"
    ])
    
    project = local.config.project_id
    role = each.value
    member = "serviceAccount:${google_service_account.kubeflow_node_sa.email}"
}

# Main Node Pool for Kubeflow
resource "google_container_node_pool" "kubeflow_main_pool" {
    name = "${local.config.cluster_name}-main-pool"
    location = local.config.gcp_region
    cluster = google_container_cluster.primary.name
    
    initial_node_count = 1
    
    autoscaling {
        min_node_count = 1
        max_node_count = 10
    }
    
    node_config {
        preemptible = false
        machine_type = "e2-standard-4"
        disk_size_gb = 100
        disk_type = "pd-standard"
        
        service_account = google_service_account.kubeflow_node_sa.email
        
        oauth_scopes = [
            "https://www.googleapis.com/auth/cloud-platform"
        ]
        
        labels = {
            purpose = "kubeflow-main"
        }
        
        metadata = {
            disable-legacy-endpoints = "true"
        }
    }
    
    management {
        auto_repair = true
        auto_upgrade = true
    }
}

# GPU Node Pool for ML workloads (optional)
resource "google_container_node_pool" "kubeflow_gpu_pool" {
    name = "${local.config.cluster_name}-gpu-pool"
    location = local.config.gcp_region
    cluster = google_container_cluster.primary.name
    
    initial_node_count = 0
    
    autoscaling {
        min_node_count = 0
        max_node_count = 3
    }
    
    node_config {
        preemptible = true
        machine_type = "n1-standard-4"
        disk_size_gb = 100
        disk_type = "pd-standard"
        
        service_account = google_service_account.kubeflow_node_sa.email
        
        oauth_scopes = [
            "https://www.googleapis.com/auth/cloud-platform"
        ]
        
        labels = {
            purpose = "kubeflow-gpu"
        }
        
        metadata = {
            disable-legacy-endpoints = "true"
        }
        
        # GPU configuration
        guest_accelerator {
            type = "nvidia-tesla-t4"
            count = 1
        }
    }
    
    management {
        auto_repair = true
        auto_upgrade = true
    }
}

# Cloud SQL instance for Kubeflow metadata
resource "google_sql_database_instance" "kubeflow_metadata" {
    name = "${local.config.cluster_name}-metadata"
    database_version = "MYSQL_8_0"
    region = local.config.gcp_region
    deletion_protection = false
    
    settings {
        tier = "db-f1-micro"
        
        backup_configuration {
            enabled = true
            start_time = "03:00"
        }
        
        ip_configuration {
            ipv4_enabled = true
            authorized_networks {
                name = "kubeflow-cluster"
                value = "0.0.0.0/0"
            }
        }
    }
}

resource "google_sql_database" "kubeflow_metadata_db" {
    name = "kubeflow_metadata"
    instance = google_sql_database_instance.kubeflow_metadata.name
}

resource "google_sql_user" "kubeflow_metadata_user" {
    name = "kubeflow"
    instance = google_sql_database_instance.kubeflow_metadata.name
    password = "kubeflow123!" # In production, use a secure password or secret manager
}

# Persistent Disk for Kubeflow artifacts
resource "google_compute_disk" "kubeflow_artifacts" {
    name = "${local.config.cluster_name}-artifacts"
    type = "pd-standard"
    zone = "${local.config.gcp_region}-a"
    size = 100
    
    labels = {
        purpose = "kubeflow-artifacts"
    }
}

# Service Account for Kubeflow pipelines
resource "google_service_account" "kubeflow_pipelines_sa" {
    account_id = "${local.config.cluster_name}-pipelines-sa"
    display_name = "Kubeflow Pipelines Service Account"
}

resource "google_project_iam_member" "kubeflow_pipelines_sa_roles" {
    for_each = toset([
        "roles/storage.admin",
        "roles/cloudsql.client",
        "roles/compute.instanceAdmin"
    ])
    
    project = local.config.project_id
    role = each.value
    member = "serviceAccount:${google_service_account.kubeflow_pipelines_sa.email}"
}

# Outputs for reference
output "cluster_name" {
    value = google_container_cluster.primary.name
}

output "cluster_endpoint" {
    value = google_container_cluster.primary.endpoint
    sensitive = true
}

output "cluster_ca_certificate" {
    value = google_container_cluster.primary.master_auth[0].cluster_ca_certificate
    sensitive = true
}

output "kubeflow_metadata_instance" {
    value = google_sql_database_instance.kubeflow_metadata.connection_name
}

output "kubeflow_artifacts_disk" {
    value = google_compute_disk.kubeflow_artifacts.self_link
}

