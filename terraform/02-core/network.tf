# =============================================================================
# NETWORKING
# =============================================================================
# Minimal VPC — only for Cloud SQL private IP.
# Cloud Run uses Google-managed networking (no VPC needed for apps).
#
# Traffic patterns:
#   Browser → Cloudflare → CF Worker → Cloud Run (HTTPS, public)
#   Cloud Run → Cloud Run: direct HTTPS + OIDC token (Google network)
#   Cloud Run → Cloud SQL: Auth Proxy sidecar (IAM tunnel, no VPC)
#   Cloud Run → Pub/Sub/GCS/Secret Mgr: Google APIs (no VPC)
#
# NO: VPC connector, NAT, load balancer, static IPs, firewall rules for apps
# =============================================================================

resource "google_compute_network" "main" {
  name                    = "tesserix-vpc"
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
}

resource "google_compute_subnetwork" "main" {
  name          = "tesserix-subnet"
  network       = google_compute_network.main.id
  region        = var.region
  ip_cidr_range = "10.0.0.0/24"
}

# Private service connection — allows Cloud SQL to have a private IP
resource "google_compute_global_address" "private_ip_range" {
  name          = "tesserix-private-ip"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 20
  network       = google_compute_network.main.id
}

resource "google_service_networking_connection" "private_vpc" {
  network                 = google_compute_network.main.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_range.name]
}

# =============================================================================
# VPC CONNECTOR (commented out — not needed with Cloud SQL Auth Proxy)
# Uncomment if you need Cloud Run → private VPC resources (e.g., Memorystore)
# Cost: ~$12/month
# =============================================================================
# resource "google_vpc_access_connector" "cloudrun" {
#   name          = "tesserix-connector"
#   region        = var.region
#   network       = google_compute_network.main.id
#   ip_cidr_range = "10.0.1.0/28"
#   min_instances = 2
#   max_instances = 3
#   machine_type  = "e2-micro"
# }
