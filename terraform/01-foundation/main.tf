terraform {
  required_version = ">= 1.5"
  required_providers {
    google = { source = "hashicorp/google", version = "~> 6.0" }
  }
  backend "gcs" {}
}

provider "google" {
  project               = var.project_id
  region                = var.region
  user_project_override = true
  billing_project       = var.project_id
}

# --- APIs ---
resource "google_project_service" "apis" {
  for_each = toset([
    # Compute
    "run.googleapis.com",
    "cloudbuild.googleapis.com",
    "artifactregistry.googleapis.com",

    # Database
    "sqladmin.googleapis.com",

    # Auth & IAM
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "identitytoolkit.googleapis.com",
    "sts.googleapis.com",

    # Secrets & Encryption
    "secretmanager.googleapis.com",
    "cloudkms.googleapis.com",

    # Messaging
    "pubsub.googleapis.com",
    "cloudtasks.googleapis.com",

    # Storage
    "storage.googleapis.com",

    # Networking (minimal — Cloud SQL private IP)
    "compute.googleapis.com",
    "servicenetworking.googleapis.com",
    "vpcaccess.googleapis.com",

    # Observability (free)
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "cloudtrace.googleapis.com",
  ])

  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

# --- Billing Budget ---
# Create manually via GCP Console: Billing → Budgets & alerts → Create budget
# ($50/month, alerts at 50%, 80%, 100%)
# The API returns INVALID_ARGUMENT on new billing accounts — console works fine.

# --- Artifact Registry ---
resource "google_artifact_registry_repository" "services" {
  location      = var.region
  repository_id = "services"
  format        = "DOCKER"
  description   = "All Tesserix service container images"

  cleanup_policies {
    id     = "keep-recent"
    action = "KEEP"
    most_recent_versions {
      keep_count = 3
    }
  }
}
