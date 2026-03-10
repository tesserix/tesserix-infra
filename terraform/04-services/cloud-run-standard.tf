# =============================================================================
# BASE CLOUD RUN SERVICES — for_each over local.base_db_services
# =============================================================================
# Services here have NO cross-standard-service URL references. They form the
# first tier that dependent services can safely reference without cycles.
# =============================================================================

resource "google_cloud_run_v2_service" "base" {
  for_each = local.base_db_services

  name                = each.key
  location            = var.region
  deletion_protection = false

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
      env {
        name  = each.value.db_ssl_key
        value = "disable" # Cloud SQL Auth Proxy sidecar provides transport encryption
      }

      # -- Optional: OPENFGA_URL (resolved via special service URIs) ----------
      dynamic "env" {
        for_each = each.value.openfga_url ? [google_cloud_run_v2_service.openfga.uri] : []
        content {
          name  = "OPENFGA_URL"
          value = env.value
        }
      }

      # -- notification-service: SendGrid sender config (bespoke) ------------
      dynamic "env" {
        for_each = each.key == "notification-service" ? { SENDGRID_FROM_EMAIL = "noreply@mark8ly.com", SENDGRID_FROM_NAME = "mark8ly" } : {}
        content {
          name  = env.key
          value = env.value
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

      startup_probe {
        http_get {
          path = "/health"
        }
        initial_delay_seconds = 2
        period_seconds        = 5
        failure_threshold     = 10
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
# DEPENDENT CLOUD RUN SERVICES — for_each over local.dependent_db_services
# =============================================================================
# Services here reference other standard services via service_urls. All targets
# are guaranteed to be in the base set, so there is no cycle.
# =============================================================================

resource "google_cloud_run_v2_service" "dependent" {
  for_each = local.dependent_db_services

  name                = each.key
  location            = var.region
  deletion_protection = false

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

      # -- Optional: APP_ENV ------------------------------------------------
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
      env {
        name  = each.value.db_ssl_key
        value = "disable" # Cloud SQL Auth Proxy sidecar provides transport encryption
      }

      # -- Optional: OPENFGA_URL ---------------------------------------------
      dynamic "env" {
        for_each = each.value.openfga_url ? [google_cloud_run_v2_service.openfga.uri] : []
        content {
          name  = "OPENFGA_URL"
          value = env.value
        }
      }

      # -- tenant-router-service domain config (static, bespoke) -------------
      dynamic "env" {
        for_each = each.key == "tenant-router-service" ? {
          PLATFORM_DOMAIN          = "tesserix.app"
          BASE_DOMAIN              = "mark8ly.com"
          CLOUDFLARE_ACCOUNT_ID    = var.cloudflare_account_id
          CLOUDFLARE_KV_NAMESPACE_ID = var.cloudflare_kv_namespace_id
          CLOUDFLARE_ZONE_ID       = var.cloudflare_zone_id
        } : {}
        content {
          name  = env.key
          value = env.value
        }
      }

      # -- Service-to-service URL references (targets are always base) -------
      dynamic "env" {
        for_each = each.value.service_urls
        content {
          name  = env.key
          value = google_cloud_run_v2_service.base[env.value].uri
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

      startup_probe {
        http_get {
          path = "/health"
        }
        initial_delay_seconds = 2
        period_seconds        = 5
        failure_threshold     = 10
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

resource "google_cloud_run_service_iam_member" "public_access" {
  for_each = local.public_services

  service  = each.value
  location = var.region
  role     = "roles/run.invoker"
  member   = "allUsers"

  depends_on = [
    google_cloud_run_v2_service.base,
    google_cloud_run_v2_service.dependent,
    google_cloud_run_v2_service.simple,
    google_cloud_run_v2_service.openfga,
    google_cloud_run_v2_service.auth_bff,
    google_cloud_run_v2_service.tesserix_home,
    google_cloud_run_v2_service.marketplace_onboarding,
    google_cloud_run_v2_service.marketplace_admin,
    google_cloud_run_v2_service.mp_storefront,
    google_cloud_run_v2_service.status_service,
  ]
}
