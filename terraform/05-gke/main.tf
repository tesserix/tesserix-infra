# =============================================================================
# GKE AUTOPILOT CLUSTER
# =============================================================================
# Autopilot: no node pool management, pay-per-pod, auto-security hardening.
# Knative Serving handles scale-to-zero for all 39 services.
# =============================================================================

data "terraform_remote_state" "core" {
  backend = "gcs"
  config = {
    bucket = var.state_bucket
    prefix = "02-core"
  }
}

# ---------------------------------------------------------------------------
# GKE subnet (separate from Cloud SQL subnet)
# ---------------------------------------------------------------------------
resource "google_compute_subnetwork" "gke" {
  name          = "tesserix-gke-subnet"
  network       = data.terraform_remote_state.core.outputs.vpc_id
  region        = var.region
  ip_cidr_range = "10.1.0.0/20"

  secondary_ip_range {
    range_name    = "gke-pods"
    ip_cidr_range = "10.4.0.0/14"
  }

  secondary_ip_range {
    range_name    = "gke-services"
    ip_cidr_range = "10.8.0.0/20"
  }

  private_ip_google_access = true
}

# ---------------------------------------------------------------------------
# GKE Autopilot cluster
# ---------------------------------------------------------------------------
resource "google_container_cluster" "main" {
  name     = var.cluster_name
  location = var.region

  enable_autopilot = true

  network    = data.terraform_remote_state.core.outputs.vpc_id
  subnetwork = google_compute_subnetwork.gke.id

  ip_allocation_policy {
    cluster_secondary_range_name  = "gke-pods"
    services_secondary_range_name = "gke-services"
  }

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
    master_ipv4_cidr_block  = "172.16.0.0/28"
  }

  dynamic "master_authorized_networks_config" {
    for_each = length(var.master_authorized_cidrs) > 0 ? [1] : []
    content {
      dynamic "cidr_blocks" {
        for_each = var.master_authorized_cidrs
        content {
          display_name = cidr_blocks.key
          cidr_block   = cidr_blocks.value
        }
      }
    }
  }

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  release_channel {
    channel = "REGULAR"
  }

  maintenance_policy {
    daily_maintenance_window {
      start_time = "22:30" # 04:00 IST (off-peak)
    }
  }

  deletion_protection = true

  resource_labels = {
    environment = "production"
    managed-by  = "terraform"
    platform    = "tesserix"
  }
}

# ---------------------------------------------------------------------------
# Cloud NAT (egress for private nodes)
# ---------------------------------------------------------------------------
resource "google_compute_router" "gke" {
  name    = "tesserix-gke-router"
  network = data.terraform_remote_state.core.outputs.vpc_id
  region  = var.region
}

resource "google_compute_router_nat" "gke" {
  name                               = "tesserix-gke-nat"
  router                             = google_compute_router.gke.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"

  subnetwork {
    name                    = google_compute_subnetwork.gke.id
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }
}

# ---------------------------------------------------------------------------
# Outputs
# ---------------------------------------------------------------------------
output "cluster_name" {
  value = google_container_cluster.main.name
}

output "cluster_endpoint" {
  value     = google_container_cluster.main.endpoint
  sensitive = true
}

output "cluster_ca_certificate" {
  value     = google_container_cluster.main.master_auth[0].cluster_ca_certificate
  sensitive = true
}

output "gke_subnet_id" {
  value = google_compute_subnetwork.gke.id
}
