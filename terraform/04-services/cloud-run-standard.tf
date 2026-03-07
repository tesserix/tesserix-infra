# =============================================================================
# STANDARD CLOUD RUN SERVICES — for_each over local.standard_db_services
# =============================================================================
# All services here follow the same structural template:
#   - Go binary on port 8080 (or per-service override)
#   - Cloud SQL proxy sidecar
#   - Standard DB_* env vars
#   - Dynamic secret injection
#   - Optional: ENVIRONMENT/GCP_PROJECT_ID, APP_ENV, OPENFGA_URL, peer URLs
# =============================================================================

resource "google_cloud_run_v2_service" "standard" {
  for_each = local.standard_db_services

  name                = each.key
  location            = var.region
  deletion_protection = false

  # CI owns the container image after initial creation — don't revert it.
  lifecycle {
    ignore_changes = [
      template[0].containers[0].image,
      template[0].containers[1].image,
    ]
  }

  template {
    service_account = local.sa_emails[each.key]

    scaling {
      min_instance_count = 0
      max_instance_count = each.value.max_instances
    }

    # -------------------------------------------------------------------------
    # Application container
    # -------------------------------------------------------------------------
    containers {
      name  = each.key
      image = each.value.image != "" ? each.value.image : "${local.gar_url}/${each.key}:latest"

      ports {
        container_port = each.value.port
      }

      resources {
        limits   = { cpu = "1", memory = each.value.memory }
        cpu_idle = true
      }

      # -- Optional: APP_ENV (tickets-service only) ---------------------------
      dynamic "env" {
        for_each = each.value.env_app_env ? ["production"] : []
        content {
          name  = "APP_ENV"
          value = env.value
        }
      }

      # -- Optional: ENVIRONMENT + GCP_PROJECT_ID ----------------------------
      dynamic "env" {
        for_each = each.value.env_project_id ? ["production"] : []
        content {
          name  = "ENVIRONMENT"
          value = env.value
        }
      }
      dynamic "env" {
        for_each = each.value.env_project_id ? [var.project_id] : []
        content {
          name  = "GCP_PROJECT_ID"
          value = env.value
        }
      }

      # -- Optional: GCP_PROJECT_ID only (no ENVIRONMENT) -------------------
      dynamic "env" {
        for_each = each.value.env_platform ? [var.project_id] : []
        content {
          name  = "GCP_PROJECT_ID"
          value = env.value
        }
      }

      # -- Standard DB env vars ----------------------------------------------
      env {
        name  = "DB_HOST"
        value = "localhost"
      }
      env {
        name  = "DB_PORT"
        value = "5432"
      }
      env {
        name  = "DB_NAME"
        value = each.value.db_name
      }
      env {
        name  = "DB_USER"
        value = each.value.db_user
      }
      # SSL mode key name varies: DB_SSLMODE vs DB_SSL_MODE (analytics-service)
      env {
        name  = each.value.db_ssl_key
        value = "disable" # Cloud SQL proxy handles TLS
      }

      # -- Optional: OPENFGA_URL (resolved via merged URI map) ---------------
      dynamic "env" {
        for_each = each.value.openfga_url ? [local.all_service_uris["openfga"]] : []
        content {
          name  = "OPENFGA_URL"
          value = env.value
        }
      }

      # -- tenant-router-service domain config (static, bespoke) -------------
      # Injected only for tenant-router-service via its unique env_platform flag
      # combined with a matching key check, avoiding a dedicated special file.
      dynamic "env" {
        for_each = each.key == "tenant-router-service" ? { PLATFORM_DOMAIN = "tesserix.app", BASE_DOMAIN = "mark8ly.com" } : {}
        content {
          name  = env.key
          value = env.value
        }
      }

      # -- Service-to-service URL references ---------------------------------
      dynamic "env" {
        for_each = each.value.service_urls
        content {
          name  = env.key
          value = local.all_service_uris[env.value]
        }
      }

      # -- Secrets -----------------------------------------------------------
      dynamic "env" {
        for_each = each.value.secrets
        content {
          name = env.key
          value_source {
            secret_key_ref {
              secret  = env.value
              version = "latest"
            }
          }
        }
      }
    }

    # -------------------------------------------------------------------------
    # Cloud SQL Auth Proxy sidecar
    # -------------------------------------------------------------------------
    containers {
      name  = "cloud-sql-proxy"
      image = "gcr.io/cloud-sql-connectors/cloud-sql-proxy:2.14.3"
      args  = [local.sql_connection]
      resources {
        limits = { cpu = "0.5", memory = "256Mi" }
      }
    }
  }
}

# =============================================================================
# SIMPLE STATELESS SERVICES — for_each over local.simple_services
# =============================================================================
# No DB, no sidecar. Used for qr-service and feature-flags-service.
# =============================================================================

resource "google_cloud_run_v2_service" "simple" {
  for_each = local.simple_services

  name                = each.key
  location            = var.region
  deletion_protection = false

  lifecycle {
    ignore_changes = [
      template[0].containers[0].image,
    ]
  }

  template {
    service_account = local.sa_emails[each.key]

    scaling {
      min_instance_count = 0
      max_instance_count = each.value.max_instances
    }

    containers {
      name  = each.key
      image = each.value.image != "" ? each.value.image : "${local.gar_url}/${each.key}:latest"

      ports {
        container_port = each.value.port
      }

      resources {
        limits   = { cpu = "1", memory = each.value.memory }
        cpu_idle = true
      }

      dynamic "env" {
        for_each = each.value.secrets
        content {
          name = env.key
          value_source {
            secret_key_ref {
              secret  = env.value
              version = "latest"
            }
          }
        }
      }
    }
  }
}

# =============================================================================
# PUBLIC ACCESS IAM — allUsers invoker for services that allow unauthenticated
# =============================================================================
# App-level GIP JWT validation (go-shared middleware) handles actual auth.
# Cloud Run IAM is set to open so Cloudflare Worker can reach these services
# without a service-account token.
# =============================================================================

resource "google_cloud_run_service_iam_member" "public_access" {
  for_each = local.public_services

  service  = each.value
  location = var.region
  role     = "roles/run.invoker"
  member   = "allUsers"

  depends_on = [
    google_cloud_run_v2_service.standard,
    google_cloud_run_v2_service.simple,
    google_cloud_run_v2_service.openfga,
    google_cloud_run_v2_service.auth_bff,
    google_cloud_run_v2_service.tesserix_home,
    google_cloud_run_v2_service.marketplace_onboarding,
    google_cloud_run_v2_service.status_service,
  ]
}
