# =============================================================================
# BLOB STORAGE — Multi-app, multi-tenant isolation
# =============================================================================
#
# Structure:
#   gs://tesserix-assets/
#   ├── platform/{tenant_id}/...         Platform-level assets
#   ├── marketplace/{tenant_id}/...      Marketplace app assets
#   │   ├── products/                    Product images
#   │   ├── store/                       Store branding
#   │   └── documents/                   Invoices, receipts
#   ├── {product-n}/{tenant_id}/...      Future products
#   └── shared/                          Cross-app (design system, etc.)
#
# Isolation:
#   - Per-app: IAM Conditions restrict service SAs to their app prefix
#   - Per-tenant: Application-level check (go-shared/storage) validates
#     tenant ID from auth context matches the path
#
# Why one bucket (not bucket-per-tenant):
#   - GCS soft limit: 100 buckets/project
#   - IAM Conditions on prefixes give equivalent isolation
#   - Simpler lifecycle rules, simpler Terraform
# =============================================================================

resource "google_storage_bucket" "assets" {
  name     = "${var.project_id}-assets"
  location = var.region

  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  versioning {
    enabled = true
  }

  lifecycle_rule {
    condition { age = 90 }
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
  }
  lifecycle_rule {
    condition { age = 365 }
    action {
      type          = "SetStorageClass"
      storage_class = "COLDLINE"
    }
  }
  lifecycle_rule {
    condition { num_newer_versions = 3 }
    action { type = "Delete" }
  }
}

# Public assets bucket (product images served via CDN/signed URLs)
resource "google_storage_bucket" "public_assets" {
  name     = "${var.project_id}-public"
  location = var.region

  uniform_bucket_level_access = true

  cors {
    origin          = ["*"]
    method          = ["GET", "HEAD"]
    response_header = ["Content-Type", "Cache-Control"]
    max_age_seconds = 3600
  }

  lifecycle_rule {
    condition { age = 365 }
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
  }
}

# Backups bucket
resource "google_storage_bucket" "backups" {
  name     = "${var.project_id}-backups"
  location = var.region

  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  lifecycle_rule {
    condition { age = 30 }
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
  }
  lifecycle_rule {
    condition { age = 365 }
    action { type = "Delete" }
  }
}
