# =============================================================================
# SERVICE ACCOUNTS — One per Cloud Run service
# =============================================================================
# Naming: sa-{service-name}
# Each SA gets ONLY the permissions its service needs.
# =============================================================================

# --- CI/CD ---
resource "google_service_account" "github_ci" {
  account_id   = "sa-github-ci"
  display_name = "GitHub Actions CI/CD"
}

resource "google_service_account_iam_member" "github_wif" {
  service_account_id = google_service_account.github_ci.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository_owner/${var.github_org}"
}

# --- Pub/Sub Invoker (push subscriptions → Cloud Run) ---
resource "google_service_account" "pubsub_invoker" {
  account_id   = "sa-pubsub-invoker"
  display_name = "Pub/Sub Push Invoker"
}

# --- Service definitions ---
locals {
  # Platform services (shared by all products)
  platform_services = {
    "auth-bff" = {
      secrets  = ["auth-bff-cookie-encryption-key", "auth-bff-csrf-secret", "openfga-preshared-key"]
      has_db   = false
      invokes  = ["openfga", "tenant-service"]
      publishes_events = true
      storage_apps     = []
    }
    "openfga" = {
      secrets  = ["openfga-preshared-key", "openfga-db-password", "openfga-db-uri"]
      has_db   = true
      invokes  = []
      publishes_events = false
      storage_apps     = []
    }
    "audit-service" = {
      secrets  = ["audit-db-password", "openfga-preshared-key"]
      has_db   = true
      invokes  = ["openfga"]
      publishes_events = false
      storage_apps     = []
    }
    "notification-service" = {
      secrets  = ["notifications-db-password", "sendgrid-api-key"]
      has_db   = true
      invokes  = []
      publishes_events = false
      storage_apps     = []
    }
    "tenant-service" = {
      secrets  = ["tenants-db-password", "openfga-preshared-key"]
      has_db   = true
      invokes  = ["openfga"]
      publishes_events = false
      storage_apps     = []
    }
    "settings-service" = {
      secrets  = ["settings-db-password"]
      has_db   = true
      invokes  = []
      publishes_events = false
      storage_apps     = []
    }
    "subscription-service" = {
      secrets  = ["subscriptions-db-password", "stripe-secret-key"]
      has_db   = true
      invokes  = []
      publishes_events = true
      storage_apps     = []
    }
    "feature-flags-service" = {
      secrets  = ["growthbook-api-key"]
      has_db   = false
      invokes  = []
      publishes_events = false
      storage_apps     = []
    }
    "document-service" = {
      secrets  = ["documents-db-password"]
      has_db   = true
      invokes  = []
      publishes_events = false
      storage_apps     = ["platform"]
    }
    "status-dashboard" = {
      secrets  = []
      has_db   = false
      invokes  = []
      publishes_events = false
      storage_apps     = []
    }
    "tesserix-home" = {
      secrets  = ["shared-internal-service-key"]
      has_db   = false
      invokes  = ["auth-bff"]
      publishes_events = false
      storage_apps     = []
    }
  }

  # Marketplace product services
  marketplace_services = {
    "mp-storefront" = {
      secrets  = []
      has_db   = false
      invokes  = ["mp-products", "mp-categories", "mp-reviews", "auth-bff"]
      publishes_events = false
      storage_apps     = []
    }
    "mp-products" = {
      secrets  = ["mp_products-db-password", "openfga-preshared-key"]
      has_db   = true
      invokes  = ["openfga"]
      publishes_events = true
      storage_apps     = ["marketplace"]
    }
    "mp-orders" = {
      secrets  = ["mp_orders-db-password", "openfga-preshared-key"]
      has_db   = true
      invokes  = ["openfga", "mp-inventory", "mp-payments", "notification-service"]
      publishes_events = true
      storage_apps     = []
    }
    "mp-payments" = {
      secrets  = ["mp_payments-db-password", "stripe-secret-key", "stripe-webhook-secret"]
      has_db   = true
      invokes  = ["openfga"]
      publishes_events = true
      storage_apps     = []
    }
    "mp-inventory" = {
      secrets  = ["mp_inventory-db-password"]
      has_db   = true
      invokes  = []
      publishes_events = true
      storage_apps     = []
    }
    "mp-shipping" = {
      secrets  = ["mp_shipping-db-password"]
      has_db   = true
      invokes  = []
      publishes_events = false
      storage_apps     = []
    }
    "mp-categories" = {
      secrets  = ["mp_categories-db-password"]
      has_db   = true
      invokes  = []
      publishes_events = false
      storage_apps     = []
    }
    "mp-coupons" = {
      secrets  = ["mp_coupons-db-password"]
      has_db   = true
      invokes  = []
      publishes_events = false
      storage_apps     = []
    }
    "mp-reviews" = {
      secrets  = ["mp_reviews-db-password", "openfga-preshared-key"]
      has_db   = true
      invokes  = ["openfga"]
      publishes_events = false
      storage_apps     = ["marketplace"]
    }
    "mp-vendors" = {
      secrets  = ["mp_vendors-db-password", "openfga-preshared-key"]
      has_db   = true
      invokes  = ["openfga"]
      publishes_events = false
      storage_apps     = ["marketplace"]
    }
    "mp-customers" = {
      secrets  = ["mp_customers-db-password", "openfga-preshared-key"]
      has_db   = true
      invokes  = ["openfga"]
      publishes_events = false
      storage_apps     = []
    }
  }

  all_services = merge(local.platform_services, local.marketplace_services)
}

# --- Create all service accounts ---
resource "google_service_account" "services" {
  for_each     = local.all_services
  account_id   = "sa-${each.key}"
  display_name = "${each.key} Cloud Run SA"
}
