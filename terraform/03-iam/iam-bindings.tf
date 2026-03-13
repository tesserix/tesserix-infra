# =============================================================================
# IAM BINDINGS — Least privilege per service
# =============================================================================

# --- CI/CD ---
resource "google_project_iam_member" "github_ci" {
  for_each = toset([
    "roles/artifactregistry.writer",
    "roles/run.developer",
    "roles/iam.serviceAccountUser",
  ])
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.github_ci.email}"
}

# --- Cloud SQL Client (services with databases) ---
resource "google_project_iam_member" "cloudsql_client" {
  for_each = { for name, cfg in local.all_services : name => cfg if cfg.has_db }
  project  = var.project_id
  role     = "roles/cloudsql.client"
  member   = "serviceAccount:${google_service_account.services[each.key].email}"
}

# --- Secret Manager (per-secret access, NOT project-wide) ---
resource "google_secret_manager_secret_iam_member" "service_secrets" {
  for_each = {
    for pair in flatten([
      for svc_name, cfg in local.all_services : [
        for secret_name in cfg.secrets : {
          key    = "${svc_name}--${secret_name}"
          svc    = svc_name
          secret = secret_name
        }
      ]
    ]) : pair.key => pair
  }

  secret_id = each.value.secret
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.services[each.value.svc].email}"
}

# --- Identity Platform Admin (tenant-scoped user management) ---
resource "google_project_iam_member" "identityplatform_admin" {
  for_each = toset(["tenant-service"])
  project  = var.project_id
  role     = "roles/identityplatform.admin"
  member   = "serviceAccount:${google_service_account.services[each.key].email}"
}

# --- Service Usage Consumer (required for Identity Toolkit API calls) ---
resource "google_project_iam_member" "service_usage_consumer" {
  for_each = toset(["tenant-service"])
  project  = var.project_id
  role     = "roles/serviceusage.serviceUsageConsumer"
  member   = "serviceAccount:${google_service_account.services[each.key].email}"
}

# --- Token Creator (custom token signing for social auth flow) ---
resource "google_project_iam_member" "token_creator" {
  for_each = toset(["tenant-service"])
  project  = var.project_id
  role     = "roles/iam.serviceAccountTokenCreator"
  member   = "serviceAccount:${google_service_account.services[each.key].email}"
}

# --- Pub/Sub Publisher ---
resource "google_project_iam_member" "pubsub_publisher" {
  for_each = { for name, cfg in local.all_services : name => cfg if cfg.publishes_events }
  project  = var.project_id
  role     = "roles/pubsub.publisher"
  member   = "serviceAccount:${google_service_account.services[each.key].email}"
}

# --- Service-to-Service Invocation ---
# On GKE: handled by Istio authorization policies, not Cloud Run IAM.
# Cloud Run IAM bindings removed during GKE migration.

# --- Blob Storage (per-app prefix isolation via IAM Conditions) ---
resource "google_storage_bucket_iam_member" "service_storage" {
  for_each = {
    for pair in flatten([
      for svc_name, cfg in local.all_services : [
        for app in cfg.storage_apps : {
          key = "${svc_name}--${app}"
          svc = svc_name
          app = app
        }
      ]
    ]) : pair.key => pair
  }

  bucket = data.terraform_remote_state.core.outputs.assets_bucket
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.services[each.value.svc].email}"

  condition {
    title      = "${each.value.svc}-${each.value.app}-only"
    expression = "resource.name.startsWith('projects/_/buckets/${data.terraform_remote_state.core.outputs.assets_bucket}/objects/${each.value.app}/')"
  }
}

# Public assets — products, reviews, vendors can write public images
resource "google_storage_bucket_iam_member" "service_public_storage" {
  for_each = {
    for pair in flatten([
      for svc_name, cfg in local.all_services : [
        for app in cfg.storage_apps : {
          key = "${svc_name}--${app}-public"
          svc = svc_name
          app = app
        }
      ]
    ]) : pair.key => pair
  }

  bucket = data.terraform_remote_state.core.outputs.public_assets_bucket
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.services[each.value.svc].email}"

  condition {
    title      = "${each.value.svc}-${each.value.app}-public-only"
    expression = "resource.name.startsWith('projects/_/buckets/${data.terraform_remote_state.core.outputs.public_assets_bucket}/objects/${each.value.app}/')"
  }
}
