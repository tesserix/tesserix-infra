# =============================================================================
# Google Identity Platform — Multi-Tenant Configuration
# =============================================================================
# Per-product GIP tenants provide user pool isolation between products.
# Each product gets an "internal" tenant (staff/admins) and a "customer" tenant
# (end-users). GIP tenants are free — cost is per MAU, not per tenant.
#
# OAuth clients are created in GCP Console (Credentials page), not here.
# Authorized domains are project-level and cover all tenants.
# =============================================================================

# --- Identity Platform Project-Level Config ---
resource "google_identity_platform_config" "default" {
  project = var.project_id

  # Authorized domains apply to ALL tenants in the project.
  # Wildcard subdomains are not supported here — GIP auto-allows
  # subdomains of listed domains for OAuth redirects.
  authorized_domains = [
    "tesserix.app",
    "mark8ly.com",
    "localhost",
  ]

  sign_in {
    allow_duplicate_emails = false

    email {
      enabled           = true
      password_required = true
    }
  }
}

# --- Platform Tenant (Tesserix Home) ---
# Platform super-admins who manage the entire Tesserix platform.
# Actual tenant ID (created via REST API): Platform-e1vyf
# terraform import google_identity_platform_tenant.platform projects/<project_id>/tenants/Platform-e1vyf
resource "google_identity_platform_tenant" "platform" {
  project      = var.project_id
  display_name = "Platform"

  allow_password_signup = true

  depends_on = [google_identity_platform_config.default]
}

# --- Marketplace Internal Tenant ---
# Marketplace store admins, staff, and onboarding users.
# Actual tenant ID (created via REST API): MP-Internal-uidfu
# terraform import google_identity_platform_tenant.mp_internal projects/<project_id>/tenants/MP-Internal-uidfu
resource "google_identity_platform_tenant" "mp_internal" {
  project      = var.project_id
  display_name = "Marketplace Internal"

  allow_password_signup = true

  depends_on = [google_identity_platform_config.default]
}

# --- Marketplace Customer Tenant ---
# Marketplace storefront end-users (shoppers).
# Actual tenant ID (created via REST API): MP-Customer-cgob2
# terraform import google_identity_platform_tenant.mp_customer projects/<project_id>/tenants/MP-Customer-cgob2
resource "google_identity_platform_tenant" "mp_customer" {
  project      = var.project_id
  display_name = "Marketplace Customer"

  allow_password_signup = true

  depends_on = [google_identity_platform_config.default]
}
