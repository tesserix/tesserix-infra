# =============================================================================
# WORKLOAD IDENTITY — K8s ServiceAccount → GCP ServiceAccount bindings
# =============================================================================
# Maps each Knative service's KSA to the existing per-service GSA from 03-iam.
# This replaces Cloud Run's native SA assignment.
# =============================================================================

data "terraform_remote_state" "iam" {
  backend = "gcs"
  config = {
    bucket = var.state_bucket
    prefix = "03-iam"
  }
}

# Namespace → service mapping (matches k8s/apps/ directory structure)
locals {
  workload_identity_bindings = {
    # platform namespace
    "platform/auth-bff"        = "sa-auth-bff"
    "platform/tesserix-home"   = "sa-tesserix-home"

    # shared namespace
    "shared/openfga"               = "sa-openfga"
    "shared/audit-service"         = "sa-audit-service"
    "shared/tenant-service"        = "sa-tenant-service"
    "shared/notification-service"  = "sa-notification-service"
    "shared/verification-service"  = "sa-verification-service"
    "shared/subscription-service"  = "sa-subscription-service"
    "shared/document-service"      = "sa-document-service"
    "shared/location-service"      = "sa-location-service"
    "shared/settings-service"      = "sa-settings-service"
    "shared/tenant-router-service" = "sa-tenant-router-service"
    "shared/tickets-service"       = "sa-tickets-service"
    "shared/analytics-service"     = "sa-analytics-service"

    # marketplace namespace
    "marketplace/mp-products"             = "sa-mp-products"
    "marketplace/mp-orders"               = "sa-mp-orders"
    "marketplace/mp-payments"             = "sa-mp-payments"
    "marketplace/mp-inventory"            = "sa-mp-inventory"
    "marketplace/mp-shipping"             = "sa-mp-shipping"
    "marketplace/mp-categories"           = "sa-mp-categories"
    "marketplace/mp-coupons"              = "sa-mp-coupons"
    "marketplace/mp-reviews"              = "sa-mp-reviews"
    "marketplace/mp-vendors"              = "sa-mp-vendors"
    "marketplace/mp-customers"            = "sa-mp-customers"
    "marketplace/mp-staff"                = "sa-mp-staff"
    "marketplace/mp-content"              = "sa-mp-content"
    "marketplace/mp-approvals"            = "sa-mp-approvals"
    "marketplace/mp-gift-cards"           = "sa-mp-gift-cards"
    "marketplace/mp-tax"                  = "sa-mp-tax"
    "marketplace/mp-marketing"            = "sa-mp-marketing"
    "marketplace/mp-connector"            = "sa-mp-connector"
    "marketplace/marketplace-admin"       = "sa-marketplace-admin"
    "marketplace/marketplace-onboarding"  = "sa-marketplace-onboarding"
    "marketplace/mp-storefront"           = "sa-mp-storefront"

    # stateless namespace (deployed to shared)
    "shared/qr-service"             = "sa-qr-service"
    "shared/feature-flags-service"  = "sa-feature-flags-service"
    "shared/status-service"         = "sa-status-service"
  }

  # ESO controller needs secret access across all namespaces
  eso_namespaces = ["platform", "shared", "marketplace"]
}

# Bind each KSA to its corresponding GSA
resource "google_service_account_iam_member" "workload_identity" {
  for_each = local.workload_identity_bindings

  service_account_id = "projects/${var.project_id}/serviceAccounts/${each.value}@${var.project_id}.iam.gserviceaccount.com"
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[${each.key}]"
}

# ESO controller GSA — needs secretmanager.secretAccessor
resource "google_service_account" "eso" {
  account_id   = "sa-eso-controller"
  display_name = "External Secrets Operator"
}

resource "google_project_iam_member" "eso_secret_accessor" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.eso.email}"
}

resource "google_service_account_iam_member" "eso_workload_identity" {
  service_account_id = google_service_account.eso.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[external-secrets/external-secrets]"
}
