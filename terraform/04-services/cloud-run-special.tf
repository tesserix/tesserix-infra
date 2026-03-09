# =============================================================================
# SPECIAL CLOUD RUN SERVICES — individually defined
# =============================================================================
# These services are excluded from the for_each map because they have unique
# characteristics that cannot be expressed cleanly in the standard schema:
#
#   openfga             — third-party image, preshared-key auth model, 512Mi RAM
#   auth-bff            — no DB/sidecar, GIP API key var, PLATFORM_CLIENT_SECRET
#   tesserix-home       — Next.js (port 3000), 512Mi, many cross-service URL refs
#   marketplace-onboarding — Next.js (port 3000), 512Mi, custom CONTENT_DB_* names
#   marketplace-admin   — Next.js (port 3000), 512Mi, many marketplace service refs
#   status-service      — placeholder image (gcr.io/cloudrun/hello), no secrets
# =============================================================================

# --- OpenFGA (authorization engine) -----------------------------------------
resource "google_cloud_run_v2_service" "openfga" {
  name                = "openfga"
  location            = var.region
  deletion_protection = false

  template {
    service_account = local.sa_emails["openfga"]

    scaling {
      min_instance_count = 0
      max_instance_count = 5
    }

    containers {
      name  = "openfga"
      image = "openfga/openfga:latest"
      args  = ["run"]

      ports {
        container_port = 8080
      }

      resources {
        limits   = { cpu = "1", memory = "512Mi" }
        cpu_idle = true
      }

      env {
        name  = "OPENFGA_DATASTORE_ENGINE"
        value = "postgres"
      }
      env {
        name = "OPENFGA_DATASTORE_URI"
        value_source {
          secret_key_ref {
            secret  = "openfga-db-uri"
            version = "latest"
          }
        }
      }
      env {
        name  = "OPENFGA_AUTHN_METHOD"
        value = "preshared"
      }
      env {
        name = "OPENFGA_AUTHN_PRESHARED_KEYS"
        value_source {
          secret_key_ref {
            secret  = "openfga-preshared-key"
            version = "latest"
          }
        }
      }
    }

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

# --- Auth BFF ----------------------------------------------------------------
resource "google_cloud_run_v2_service" "auth_bff" {
  name                = "auth-bff"
  location            = var.region
  deletion_protection = false

  lifecycle {
    ignore_changes = [template[0].containers[0].image]
  }

  template {
    service_account = local.sa_emails["auth-bff"]

    scaling {
      min_instance_count = 0
      max_instance_count = 10
    }

    containers {
      name  = "auth-bff"
      image = "${local.gar_url}/auth-bff:latest"

      ports {
        container_port = 8080
      }

      resources {
        limits   = { cpu = "1", memory = "256Mi" }
        cpu_idle = true
      }

      env {
        name  = "APP_ENV"
        value = "production"
      }
      env {
        name  = "GCP_PROJECT_ID"
        value = var.project_id
      }
      env {
        name  = "GIP_API_KEY"
        value = var.identity_platform_api_key
      }
      env {
        name  = "OPENFGA_URL"
        value = google_cloud_run_v2_service.openfga.uri
      }
      # TODO: uncomment after deploying tenant-service
      # env {
      #   name  = "TENANT_SERVICE_URL"
      #   value = google_cloud_run_v2_service.base["tenant-service"].uri
      # }

      env {
        name = "COOKIE_ENCRYPTION_KEY"
        value_source {
          secret_key_ref {
            secret  = "auth-bff-cookie-encryption-key"
            version = "latest"
          }
        }
      }
      env {
        name = "CSRF_SECRET"
        value_source {
          secret_key_ref {
            secret  = "auth-bff-csrf-secret"
            version = "latest"
          }
        }
      }
      env {
        name = "OPENFGA_API_KEY"
        value_source {
          secret_key_ref {
            secret  = "openfga-preshared-key"
            version = "latest"
          }
        }
      }
      env {
        name = "PLATFORM_CLIENT_SECRET"
        value_source {
          secret_key_ref {
            secret  = "platform-client-secret"
            version = "latest"
          }
        }
      }
    }
  }
}

# --- Tesserix Home (Next.js admin portal) ------------------------------------
resource "google_cloud_run_v2_service" "tesserix_home" {
  name                = "tesserix-home"
  location            = var.region
  deletion_protection = false

  lifecycle {
    ignore_changes = [template[0].containers[0].image]
  }

  template {
    service_account = local.sa_emails["tesserix-home"]

    scaling {
      min_instance_count = 0
      max_instance_count = 5
    }

    containers {
      name  = "tesserix-home"
      image = "${local.gar_url}/tesserix-home:latest"

      ports {
        container_port = 3000
      }

      resources {
        limits   = { cpu = "1", memory = "512Mi" }
        cpu_idle = true
      }

      env {
        name  = "NODE_ENV"
        value = "production"
      }
      env {
        name  = "NEXT_TELEMETRY_DISABLED"
        value = "1"
      }
      env {
        name  = "NEXT_PUBLIC_SITE_URL"
        value = "https://tesserix.app"
      }
      env {
        name  = "NEXT_PUBLIC_ONBOARDING_SITE_URL"
        value = "https://mark8ly.com"
      }
      env {
        name  = "PLATFORM_DOMAIN"
        value = "tesserix.app"
      }
      env {
        name  = "CSRF_ALLOWED_DOMAINS"
        value = "tesserix.app"
      }

      # Cross-service URLs — resolved after all services are planned
      env {
        name  = "AUTH_BFF_URL"
        value = google_cloud_run_v2_service.auth_bff.uri
      }
      env {
        name  = "TENANT_SERVICE_URL"
        value = google_cloud_run_v2_service.base["tenant-service"].uri
      }
      env {
        name  = "TICKETS_SERVICE_URL"
        value = "${google_cloud_run_v2_service.dependent["tickets-service"].uri}/api/v1"
      }
      env {
        name  = "AUDIT_SERVICE_URL"
        value = "${google_cloud_run_v2_service.base["audit-service"].uri}/api/v1"
      }
      env {
        name  = "FEATURE_FLAGS_SERVICE_URL"
        value = "${google_cloud_run_v2_service.simple["feature-flags-service"].uri}/api/v1"
      }
      env {
        name  = "NOTIFICATION_SERVICE_URL"
        value = "${google_cloud_run_v2_service.base["notification-service"].uri}/api/v1"
      }
      env {
        name  = "STATUS_SERVICE_URL"
        value = "${google_cloud_run_v2_service.status_service.uri}/api/v1"
      }
      env {
        name  = "SUBSCRIPTION_SERVICE_URL"
        value = google_cloud_run_v2_service.dependent["subscription-service"].uri
      }

      env {
        name = "INTERNAL_SERVICE_KEY"
        value_source {
          secret_key_ref {
            secret  = "shared-internal-service-key"
            version = "latest"
          }
        }
      }
    }
  }
}

# --- Marketplace Onboarding (Next.js) ----------------------------------------
resource "google_cloud_run_v2_service" "marketplace_onboarding" {
  name                = "marketplace-onboarding"
  location            = var.region
  deletion_protection = false

  lifecycle {
    ignore_changes = [
      template[0].containers[0].image,
      template[0].containers[1].image,
    ]
  }

  template {
    service_account = local.sa_emails["marketplace-onboarding"]

    scaling {
      min_instance_count = 0
      max_instance_count = 5
    }

    containers {
      name  = "marketplace-onboarding"
      image = "gcr.io/cloudrun/hello:latest"

      ports {
        container_port = 3000
      }

      resources {
        limits   = { cpu = "1", memory = "512Mi" }
        cpu_idle = true
      }

      env {
        name  = "NODE_ENV"
        value = "production"
      }
      env {
        name  = "NEXT_TELEMETRY_DISABLED"
        value = "1"
      }
      env {
        name  = "GCP_PROJECT_ID"
        value = var.project_id
      }
      env {
        name  = "NEXT_PUBLIC_SITE_URL"
        value = "https://mark8ly.com"
      }
      env {
        name  = "NEXT_PUBLIC_BASE_DOMAIN"
        value = "mark8ly.com"
      }
      env {
        name  = "CSRF_ALLOWED_DOMAINS"
        value = "mark8ly.com"
      }

      # Cross-service URLs
      env {
        name  = "AUTH_BFF_URL"
        value = google_cloud_run_v2_service.auth_bff.uri
      }
      env {
        name  = "TENANT_SERVICE_URL"
        value = google_cloud_run_v2_service.base["tenant-service"].uri
      }
      env {
        name  = "LOCATION_SERVICE_URL"
        value = google_cloud_run_v2_service.base["location-service"].uri
      }
      env {
        name  = "VERIFICATION_SERVICE_URL"
        value = google_cloud_run_v2_service.dependent["verification-service"].uri
      }
      env {
        name  = "TENANT_ROUTER_URL"
        value = google_cloud_run_v2_service.dependent["tenant-router-service"].uri
      }

      # Content DB (uses CONTENT_DB_* prefix — not standard DB_* names)
      env {
        name  = "CONTENT_DB_HOST"
        value = "localhost"
      }
      env {
        name  = "CONTENT_DB_PORT"
        value = "5432"
      }
      env {
        name  = "CONTENT_DB_NAME"
        value = "mp_onboarding_db"
      }
      env {
        name  = "CONTENT_DB_USER"
        value = "mp_onboarding_user"
      }
      env {
        name  = "CONTENT_DB_SSLMODE"
        value = "disable"
      }

      env {
        name = "CONTENT_DB_PASSWORD"
        value_source {
          secret_key_ref {
            secret  = "mp_onboarding-db-password"
            version = "latest"
          }
        }
      }
      env {
        name = "INTERNAL_SERVICE_KEY"
        value_source {
          secret_key_ref {
            secret  = "shared-internal-service-key"
            version = "latest"
          }
        }
      }
    }

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

# --- Marketplace Admin (Next.js admin panel) ----------------------------------
resource "google_cloud_run_v2_service" "marketplace_admin" {
  name                = "marketplace-admin"
  location            = var.region
  deletion_protection = false

  lifecycle {
    ignore_changes = [template[0].containers[0].image]
  }

  template {
    service_account = local.sa_emails["marketplace-admin"]

    scaling {
      min_instance_count = 0
      max_instance_count = 5
    }

    containers {
      name  = "marketplace-admin"
      image = "gcr.io/cloudrun/hello:latest"

      ports {
        container_port = 3000
      }

      resources {
        limits   = { cpu = "1", memory = "512Mi" }
        cpu_idle = true
      }

      env {
        name  = "NODE_ENV"
        value = "production"
      }
      env {
        name  = "NEXT_TELEMETRY_DISABLED"
        value = "1"
      }
      env {
        name  = "GCP_PROJECT_ID"
        value = var.project_id
      }
      env {
        name  = "NEXT_PUBLIC_BASE_DOMAIN"
        value = "mark8ly.com"
      }
      env {
        name  = "CSRF_ALLOWED_DOMAINS"
        value = "mark8ly.com"
      }

      # Cross-service URLs
      env {
        name  = "AUTH_BFF_URL"
        value = google_cloud_run_v2_service.auth_bff.uri
      }
      env {
        name  = "TENANT_SERVICE_URL"
        value = google_cloud_run_v2_service.base["tenant-service"].uri
      }
      env {
        name  = "CATEGORIES_SERVICE_URL"
        value = "${google_cloud_run_v2_service.base["mp-categories"].uri}/api/v1"
      }
      env {
        name  = "PRODUCTS_SERVICE_URL"
        value = "${google_cloud_run_v2_service.base["mp-products"].uri}/api/v1"
      }
      env {
        name  = "ORDERS_SERVICE_URL"
        value = "${google_cloud_run_v2_service.dependent["mp-orders"].uri}/api/v1"
      }
      env {
        name  = "VENDORS_SERVICE_URL"
        value = "${google_cloud_run_v2_service.base["mp-vendors"].uri}/api/v1"
      }
      env {
        name  = "CUSTOMERS_SERVICE_URL"
        value = "${google_cloud_run_v2_service.base["mp-customers"].uri}/api/v1"
      }
      env {
        name  = "REVIEWS_SERVICE_URL"
        value = "${google_cloud_run_v2_service.base["mp-reviews"].uri}/api/v1"
      }
      env {
        name  = "COUPONS_SERVICE_URL"
        value = "${google_cloud_run_v2_service.base["mp-coupons"].uri}/api/v1"
      }
      env {
        name  = "SHIPPING_SERVICE_URL"
        value = "${google_cloud_run_v2_service.base["mp-shipping"].uri}/api/v1"
      }
      env {
        name  = "TICKETS_SERVICE_URL"
        value = "${google_cloud_run_v2_service.dependent["tickets-service"].uri}/api/v1"
      }
      env {
        name  = "SETTINGS_SERVICE_URL"
        value = google_cloud_run_v2_service.base["settings-service"].uri
      }
      env {
        name  = "SUBSCRIPTION_SERVICE_URL"
        value = google_cloud_run_v2_service.dependent["subscription-service"].uri
      }
      env {
        name  = "NOTIFICATION_SERVICE_URL"
        value = "${google_cloud_run_v2_service.base["notification-service"].uri}/api/v1"
      }
      env {
        name  = "FEATURE_FLAGS_SERVICE_URL"
        value = "${google_cloud_run_v2_service.simple["feature-flags-service"].uri}/api/v1"
      }
      env {
        name  = "DOCUMENT_SERVICE_URL"
        value = google_cloud_run_v2_service.base["document-service"].uri
      }
      env {
        name  = "LOCATION_SERVICE_URL"
        value = google_cloud_run_v2_service.base["location-service"].uri
      }

      env {
        name = "INTERNAL_SERVICE_KEY"
        value_source {
          secret_key_ref {
            secret  = "shared-internal-service-key"
            version = "latest"
          }
        }
      }
    }
  }
}

# --- Marketplace Storefront (Next.js) -----------------------------------------
resource "google_cloud_run_v2_service" "mp_storefront" {
  name                = "mp-storefront"
  location            = var.region
  deletion_protection = false

  lifecycle {
    ignore_changes = [template[0].containers[0].image]
  }

  template {
    service_account = local.sa_emails["mp-storefront"]

    scaling {
      min_instance_count = 0
      max_instance_count = 5
    }

    containers {
      name  = "mp-storefront"
      image = "gcr.io/cloudrun/hello:latest"

      ports {
        container_port = 3000
      }

      resources {
        limits   = { cpu = "1", memory = "512Mi" }
        cpu_idle = true
      }

      env {
        name  = "NODE_ENV"
        value = "production"
      }
      env {
        name  = "NEXT_TELEMETRY_DISABLED"
        value = "1"
      }
      env {
        name  = "NEXT_PUBLIC_BASE_DOMAIN"
        value = "mark8ly.com"
      }

      # Cross-service URLs
      env {
        name  = "AUTH_BFF_URL"
        value = google_cloud_run_v2_service.auth_bff.uri
      }
      env {
        name  = "PRODUCTS_SERVICE_URL"
        value = "${google_cloud_run_v2_service.base["mp-products"].uri}/api/v1"
      }
      env {
        name  = "CATEGORIES_SERVICE_URL"
        value = "${google_cloud_run_v2_service.base["mp-categories"].uri}/api/v1"
      }
      env {
        name  = "REVIEWS_SERVICE_URL"
        value = "${google_cloud_run_v2_service.base["mp-reviews"].uri}/api/v1"
      }
    }
  }
}

# --- Status Service -----------------------------------------------------------
resource "google_cloud_run_v2_service" "status_service" {
  name                = "status-service"
  location            = var.region
  deletion_protection = false

  lifecycle {
    ignore_changes = [template[0].containers[0].image]
  }

  template {
    service_account = local.sa_emails["status-service"]

    scaling {
      min_instance_count = 0
      max_instance_count = 2
    }

    containers {
      name  = "status-service"
      image = "gcr.io/cloudrun/hello:latest"

      ports {
        container_port = 8080
      }

      resources {
        limits   = { cpu = "1", memory = "256Mi" }
        cpu_idle = true
      }
    }
  }
}
