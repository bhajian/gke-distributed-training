provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.node_locations[0]
}

resource "google_compute_network" "vpc" {
  name                    = var.network_name
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "subnet" {
  name                     = var.subnet_name
  region                   = var.region
  network                  = google_compute_network.vpc.id
  ip_cidr_range            = var.subnet_cidr
  private_ip_google_access = true

  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = var.pods_cidr
  }

  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = var.services_cidr
  }
}

resource "google_compute_firewall" "allow_ssh" {
  name    = "${var.network_name}-allow-ssh"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  allow {
    protocol = "icmp"
  }

  source_ranges = [var.admin_cidr]
  target_tags   = ["gke-node"]
}

resource "google_container_cluster" "gke" {
  name     = var.cluster_name
  location = var.region

  network    = google_compute_network.vpc.name
  subnetwork = google_compute_subnetwork.subnet.name

  remove_default_node_pool = true
  initial_node_count       = 1

  release_channel {
    channel = "REGULAR"
  }

  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  deletion_protection = false
}

resource "google_container_node_pool" "cpu" {
  name       = "${var.cluster_name}-cpu"
  location   = var.region
  cluster    = google_container_cluster.gke.name
  node_count = var.cpu_node_count

  node_locations = var.node_locations

  node_config {
    machine_type = var.cpu_machine_type
    image_type   = "COS_CONTAINERD"
    disk_size_gb = 100

    tags = ["gke-node"]

    metadata = {
      disable-legacy-endpoints = "true"
    }

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }
}

resource "google_container_node_pool" "gpu" {
  name       = "${var.cluster_name}-a100"
  location   = var.region
  cluster    = google_container_cluster.gke.name
  node_count = var.gpu_node_count

  node_locations = var.node_locations

  node_config {
    machine_type = var.gpu_machine_type
    image_type   = "COS_CONTAINERD"
    disk_size_gb = 200
    disk_type    = "pd-ssd"

    tags = ["gke-node", "gpu-node"]

    labels = {
      accelerator = "a100"
    }

    metadata = {
      disable-legacy-endpoints = "true"
    }

    taint {
      key    = "nvidia.com/gpu"
      value  = "present"
      effect = "NO_SCHEDULE"
    }

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]

    dynamic "guest_accelerator" {
      for_each = var.enable_guest_accelerator ? [1] : []
      content {
        type  = var.gpu_type
        count = var.gpu_count_per_node

        gpu_driver_installation_config {
          gpu_driver_version = var.gpu_driver_version
        }
      }
    }
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }
}
