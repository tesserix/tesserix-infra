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
      secrets  = ["auth-bff-cookie-encryption-key", "auth-bff-csrf-secret", "openfga-preshared-key", "platform-client-secret", "mp-admin-client-secret", "mp-storefront-client-secret"]
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
      secrets  = ["settings-db-password", "openfga-preshared-key", "openfga-platform-store-id"]
      has_db   = true
      invokes  = ["openfga"]
      publishes_events = true
      storage_apps     = []
    }
    "subscription-service" = {
      secrets  = ["subscriptions-db-password", "stripe-secret-key", "stripe-webhook-secret"]
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
    "tickets-service" = {
      secrets  = ["tickets-db-password", "openfga-preshared-key", "openfga-marketplace-store-id"]
      has_db   = true
      invokes  = ["openfga", "tenant-service", "notification-service", "document-service"]
      publishes_events = true
      storage_apps     = []
    }
    "document-service" = {
      secrets  = ["documents-db-password"]
      has_db   = true
      invokes  = []
      publishes_events = false
      storage_apps     = ["platform"]
    }
    "status-service" = {
      secrets  = []
      has_db   = false
      invokes  = []
      publishes_events = false
      storage_apps     = []
    }
    "qr-service" = {
      secrets  = []
      has_db   = false
      invokes  = []
      publishes_events = false
      storage_apps     = []
    }
    "analytics-service" = {
      secrets  = ["analytics-db-password"]
      has_db   = true
      invokes  = []
      publishes_events = false
      storage_apps     = []
    }
    "verification-service" = {
      secrets  = ["verifications-db-password", "shared-internal-service-key", "verification-encryption-key"]
      has_db   = true
      invokes  = ["notification-service"]
      publishes_events = true
      storage_apps     = []
    }
    "tesserix-home" = {
      secrets  = ["shared-internal-service-key"]
      has_db   = false
      invokes  = ["auth-bff"]
      publishes_events = false
      storage_apps     = []
    }
    "location-service" = {
      secrets  = ["location-db-password", "openfga-preshared-key", "openfga-marketplace-store-id"]
      has_db   = true
      invokes  = ["openfga"]
      publishes_events = false
      storage_apps     = []
    }
    "tenant-router-service" = {
      secrets  = ["tenant_router-db-password", "shared-internal-service-key", "cloudflare-api-token"]
      has_db   = true
      invokes  = ["notification-service", "audit-service"]
      publishes_events = true
      storage_apps     = []
    }
  }

  # Marketplace product services
  marketplace_services = {
    "marketplace-onboarding" = {
      secrets  = ["mp_onboarding-db-password", "shared-internal-service-key"]
      has_db   = true
      invokes  = ["auth-bff", "tenant-service", "location-service", "verification-service", "tenant-router-service"]
      publishes_events = false
      storage_apps     = []
    }
    "marketplace-admin" = {
      secrets  = ["shared-internal-service-key"]
      has_db   = false
      invokes  = ["auth-bff", "tenant-service", "tenant-router-service", "mp-products", "mp-orders", "mp-vendors", "mp-customers", "mp-categories", "mp-coupons", "mp-reviews", "mp-shipping", "settings-service", "subscription-service", "tickets-service", "notification-service", "feature-flags-service", "document-service", "location-service"]
      publishes_events = false
      storage_apps     = []
    }
    "mp-storefront" = {
      secrets  = []
      has_db   = false
      invokes  = ["mp-products", "mp-categories", "mp-reviews", "auth-bff", "tenant-service", "tenant-router-service", "settings-service", "notification-service"]
      publishes_events = false
      storage_apps     = []
    }
    "mp-products" = {
      secrets  = ["mp_products-db-password", "openfga-preshared-key", "openfga-marketplace-store-id"]
      has_db   = true
      invokes  = ["openfga"]
      publishes_events = true
      storage_apps     = ["marketplace"]
    }
    "mp-orders" = {
      secrets  = ["mp_orders-db-password", "openfga-preshared-key", "openfga-marketplace-store-id"]
      has_db   = true
      invokes  = ["openfga", "mp-inventory", "mp-payments", "notification-service"]
      publishes_events = true
      storage_apps     = []
    }
    "mp-payments" = {
      secrets  = ["mp_payments-db-password", "stripe-secret-key", "stripe-webhook-secret", "openfga-preshared-key", "openfga-marketplace-store-id"]
      has_db   = true
      invokes  = ["openfga"]
      publishes_events = true
      storage_apps     = []
    }
    "mp-inventory" = {
      secrets  = ["mp_inventory-db-password", "openfga-preshared-key", "openfga-marketplace-store-id"]
      has_db   = true
      invokes  = ["openfga"]
      publishes_events = true
      storage_apps     = []
    }
    "mp-shipping" = {
      secrets  = ["mp_shipping-db-password", "openfga-preshared-key", "openfga-marketplace-store-id"]
      has_db   = true
      invokes  = ["openfga"]
      publishes_events = false
      storage_apps     = []
    }
    "mp-categories" = {
      secrets  = ["mp_categories-db-password", "openfga-preshared-key", "openfga-marketplace-store-id"]
      has_db   = true
      invokes  = ["openfga", "mp-approvals"]
      publishes_events = false
      storage_apps     = []
    }
    "mp-coupons" = {
      secrets  = ["mp_coupons-db-password", "openfga-preshared-key", "openfga-marketplace-store-id"]
      has_db   = true
      invokes  = ["openfga"]
      publishes_events = false
      storage_apps     = []
    }
    "mp-reviews" = {
      secrets  = ["mp_reviews-db-password", "openfga-preshared-key", "openfga-marketplace-store-id"]
      has_db   = true
      invokes  = ["openfga"]
      publishes_events = false
      storage_apps     = ["marketplace"]
    }
    "mp-vendors" = {
      secrets  = ["mp_vendors-db-password", "openfga-preshared-key", "openfga-marketplace-store-id"]
      has_db   = true
      invokes  = ["openfga"]
      publishes_events = false
      storage_apps     = ["marketplace"]
    }
    "mp-customers" = {
      secrets  = ["mp_customers-db-password", "openfga-preshared-key", "openfga-marketplace-store-id"]
      has_db   = true
      invokes  = ["openfga"]
      publishes_events = false
      storage_apps     = []
    }
    "mp-staff" = {
      secrets  = ["mp_staff-db-password", "openfga-preshared-key", "openfga-marketplace-store-id"]
      has_db   = true
      invokes  = ["openfga", "document-service"]
      publishes_events = true
      storage_apps     = []
    }
    "mp-content" = {
      secrets  = ["mp_content-db-password", "openfga-preshared-key", "openfga-marketplace-store-id"]
      has_db   = true
      invokes  = ["openfga"]
      publishes_events = false
      storage_apps     = []
    }
    "mp-approvals" = {
      secrets  = ["mp_approvals-db-password", "openfga-preshared-key", "openfga-marketplace-store-id"]
      has_db   = true
      invokes  = ["openfga"]
      publishes_events = true
      storage_apps     = []
    }
    "mp-gift-cards" = {
      secrets  = ["mp_gift_cards-db-password", "openfga-preshared-key", "openfga-marketplace-store-id"]
      has_db   = true
      invokes  = ["openfga"]
      publishes_events = true
      storage_apps     = []
    }
    "mp-marketing" = {
      secrets  = ["mp_marketing-db-password", "openfga-preshared-key", "openfga-marketplace-store-id"]
      has_db   = true
      invokes  = ["openfga", "notification-service"]
      publishes_events = true
      storage_apps     = []
    }
    "mp-connector" = {
      secrets  = ["mp_connector-db-password"]
      has_db   = true
      invokes  = ["mp-products", "mp-orders", "mp-inventory"]
      publishes_events = false
      storage_apps     = []
    }
    "mp-tax" = {
      secrets  = ["mp_tax-db-password", "openfga-preshared-key", "openfga-marketplace-store-id"]
      has_db   = true
      invokes  = ["openfga"]
      publishes_events = true
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
