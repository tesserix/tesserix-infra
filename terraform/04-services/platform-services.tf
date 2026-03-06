# =============================================================================
# PLATFORM SERVICES — Cloud Run definitions
# =============================================================================

# --- OpenFGA (authorization engine) ---
resource "google_cloud_run_v2_service" "openfga" {
  name     = "openfga"
  location = var.region

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

# --- Auth BFF ---
resource "google_cloud_run_v2_service" "auth_bff" {
  name     = "auth-bff"
  location = var.region

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
      #   value = google_cloud_run_v2_service.tenant_service.uri
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

# --- Audit Service ---
resource "google_cloud_run_v2_service" "audit_service" {
  name     = "audit-service"
  location = var.region

  template {
    service_account = local.sa_emails["audit-service"]

    scaling {
      min_instance_count = 0
      max_instance_count = 5
    }

    containers {
      name  = "audit-service"
      image = "${local.gar_url}/audit-service:latest"

      ports {
        container_port = 8080
      }

      resources {
        limits   = { cpu = "1", memory = "256Mi" }
        cpu_idle = true
      }

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
        value = "audit_db"
      }
      env {
        name  = "DB_USER"
        value = "audit_user"
      }
      env {
        name  = "DB_SSLMODE"
        value = "disable" # Proxy handles encryption
      }
      env {
        name  = "OPENFGA_URL"
        value = google_cloud_run_v2_service.openfga.uri
      }

      env {
        name = "DB_PASSWORD"
        value_source {
          secret_key_ref {
            secret  = "audit-db-password"
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

# --- Tenant Service ---
resource "google_cloud_run_v2_service" "tenant_service" {
  name     = "tenant-service"
  location = var.region

  template {
    service_account = local.sa_emails["tenant-service"]

    scaling {
      min_instance_count = 0
      max_instance_count = 5
    }

    containers {
      name  = "tenant-service"
      image = "${local.gar_url}/tenant-service:latest"

      ports {
        container_port = 8080
      }

      resources {
        limits   = { cpu = "1", memory = "256Mi" }
        cpu_idle = true
      }

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
        value = "tenants_db"
      }
      env {
        name  = "DB_USER"
        value = "tenants_user"
      }
      env {
        name  = "DB_SSLMODE"
        value = "disable"
      }
      env {
        name  = "OPENFGA_URL"
        value = google_cloud_run_v2_service.openfga.uri
      }

      env {
        name = "DB_PASSWORD"
        value_source {
          secret_key_ref {
            secret  = "tenants-db-password"
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

# --- Notification Service ---
resource "google_cloud_run_v2_service" "notification_service" {
  name     = "notification-service"
  location = var.region

  template {
    service_account = local.sa_emails["notification-service"]

    scaling {
      min_instance_count = 0
      max_instance_count = 5
    }

    containers {
      name  = "notification-service"
      image = "${local.gar_url}/notification-service:latest"

      ports {
        container_port = 8080
      }

      resources {
        limits   = { cpu = "1", memory = "256Mi" }
        cpu_idle = true
      }

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
        value = "notifications_db"
      }
      env {
        name  = "DB_USER"
        value = "notifications_user"
      }
      env {
        name  = "DB_SSLMODE"
        value = "disable"
      }

      env {
        name = "DB_PASSWORD"
        value_source {
          secret_key_ref {
            secret  = "notifications-db-password"
            version = "latest"
          }
        }
      }
      env {
        name = "SENDGRID_API_KEY"
        value_source {
          secret_key_ref {
            secret  = "sendgrid-api-key"
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

# --- Tickets Service ---
resource "google_cloud_run_v2_service" "tickets_service" {
  name     = "tickets-service"
  location = var.region

  template {
    service_account = local.sa_emails["tickets-service"]

    scaling {
      min_instance_count = 0
      max_instance_count = 5
    }

    containers {
      name  = "tickets-service"
      image = "${local.gar_url}/tickets-service:latest"

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
        name  = "DB_HOST"
        value = "localhost"
      }
      env {
        name  = "DB_PORT"
        value = "5432"
      }
      env {
        name  = "DB_NAME"
        value = "tickets_db"
      }
      env {
        name  = "DB_USER"
        value = "tickets_user"
      }
      env {
        name  = "DB_SSLMODE"
        value = "disable" # Proxy handles encryption
      }
      env {
        name  = "OPENFGA_URL"
        value = google_cloud_run_v2_service.openfga.uri
      }
      env {
        name  = "NOTIFICATION_SERVICE_URL"
        value = google_cloud_run_v2_service.notification_service.uri
      }
      env {
        name  = "TENANT_SERVICE_URL"
        value = google_cloud_run_v2_service.tenant_service.uri
      }

      env {
        name = "DB_PASSWORD"
        value_source {
          secret_key_ref {
            secret  = "tickets-db-password"
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

# --- Tesserix Home (Next.js admin portal) ---
resource "google_cloud_run_v2_service" "tesserix_home" {
  name     = "tesserix-home"
  location = var.region

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
        name  = "AUTH_BFF_URL"
        value = google_cloud_run_v2_service.auth_bff.uri
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

# --- Feature Flags Service ---
resource "google_cloud_run_v2_service" "feature_flags" {
  name     = "feature-flags-service"
  location = var.region

  template {
    service_account = local.sa_emails["feature-flags-service"]

    scaling {
      min_instance_count = 0
      max_instance_count = 3
    }

    containers {
      name  = "feature-flags-service"
      image = "${local.gar_url}/feature-flags-service:latest"

      ports {
        container_port = 8080
      }

      resources {
        limits   = { cpu = "0.5", memory = "128Mi" }
        cpu_idle = true
      }

      env {
        name = "GROWTHBOOK_API_KEY"
        value_source {
          secret_key_ref {
            secret  = "growthbook-api-key"
            version = "latest"
          }
        }
      }
    }
  }
}

# --- Status Dashboard ---
resource "google_cloud_run_v2_service" "status_dashboard" {
  name     = "status-dashboard"
  location = var.region

  template {
    service_account = local.sa_emails["status-dashboard"]

    scaling {
      min_instance_count = 0
      max_instance_count = 2
    }

    containers {
      name  = "status-dashboard"
      image = "${local.gar_url}/status-dashboard-service:latest"

      ports {
        container_port = 8080
      }

      resources {
        limits   = { cpu = "0.5", memory = "128Mi" }
        cpu_idle = true
      }

    }
  }
}
