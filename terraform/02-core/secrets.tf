# =============================================================================
# SECRET MANAGEMENT
# =============================================================================
# All secrets in GCP Secret Manager. Cloud Run reads them natively.
# No ESO, no K8s Secrets, no sealed secrets.
#
# Naming: {service}-{secret-name}
#   DB passwords: handled in cloud-sql.tf (auto-generated)
#   Service keys: auto-generated here
#   Third-party:  created here, value set manually via gcloud
# =============================================================================

# --- Auto-generated secrets ---
resource "random_password" "generated" {
  for_each = toset([
    "auth-bff-cookie-encryption-key",
    "auth-bff-csrf-secret",
    "openfga-preshared-key",
    "shared-internal-service-key",
  ])

  length  = 64
  special = false
}

resource "google_secret_manager_secret" "generated" {
  for_each  = random_password.generated
  secret_id = each.key
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "generated" {
  for_each    = google_secret_manager_secret.generated
  secret      = each.value.id
  secret_data = random_password.generated[each.key].result
}

# --- OpenFGA full DB URI (needed because Cloud Run can't interpolate env vars) ---
resource "google_secret_manager_secret" "openfga_db_uri" {
  secret_id = "openfga-db-uri"
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "openfga_db_uri" {
  secret      = google_secret_manager_secret.openfga_db_uri.id
  secret_data = "postgres://openfga_user:${random_password.db_passwords["openfga_db"].result}@localhost:5432/openfga_db?sslmode=disable"
}

# --- Manual secrets (create resource, set value via gcloud) ---
resource "google_secret_manager_secret" "manual" {
  for_each = toset([
    "cloudflare-api-token",
    "sendgrid-api-key",
    "stripe-secret-key",
    "stripe-webhook-secret",
    "growthbook-api-key",
    "identity-platform-smtp-password",
    "platform-client-secret",
    "mp-admin-client-secret",
    "mp-storefront-client-secret",
    "openfga-marketplace-store-id",
    "verification-encryption-key",
  ])

  secret_id = each.key
  replication {
    auto {}
  }
}
