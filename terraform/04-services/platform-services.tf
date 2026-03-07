# =============================================================================
# PLATFORM SERVICES — Cloud Run definitions
# =============================================================================

# --- OpenFGA (authorization engine) ---
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

# --- Auth BFF ---
resource "google_cloud_run_v2_service" "auth_bff" {
  name                = "auth-bff"
  location            = var.region
  deletion_protection = false

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
  name                = "audit-service"
  location            = var.region
  deletion_protection = false

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
  name                = "tenant-service"
  location            = var.region
  deletion_protection = false

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
  name                = "notification-service"
  location            = var.region
  deletion_protection = false

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
  name                = "tickets-service"
  location            = var.region
  deletion_protection = false

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
        name  = "ENVIRONMENT"
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
  name                = "tesserix-home"
  location            = var.region
  deletion_protection = false

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
        name  = "AUTH_BFF_URL"
        value = google_cloud_run_v2_service.auth_bff.uri
      }
      env {
        name  = "TENANT_SERVICE_URL"
        value = google_cloud_run_v2_service.tenant_service.uri
      }
      env {
        name  = "TICKETS_SERVICE_URL"
        value = "${google_cloud_run_v2_service.tickets_service.uri}/api/v1"
      }
      env {
        name  = "AUDIT_SERVICE_URL"
        value = "${google_cloud_run_v2_service.audit_service.uri}/api/v1"
      }
      env {
        name  = "FEATURE_FLAGS_SERVICE_URL"
        value = "${google_cloud_run_v2_service.feature_flags.uri}/api/v1"
      }
      env {
        name  = "NOTIFICATION_SERVICE_URL"
        value = "${google_cloud_run_v2_service.notification_service.uri}/api/v1"
      }
      env {
        name  = "STATUS_DASHBOARD_SERVICE_URL"
        value = "${google_cloud_run_v2_service.status_service.uri}/api/v1"
      }
      env {
        name  = "SUBSCRIPTION_SERVICE_URL"
        value = google_cloud_run_v2_service.subscription_service.uri
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

# --- Subscription Service ---
resource "google_cloud_run_v2_service" "subscription_service" {
  name                = "subscription-service"
  location            = var.region
  deletion_protection = false

  template {
    service_account = local.sa_emails["subscription-service"]

    scaling {
      min_instance_count = 0
      max_instance_count = 5
    }

    containers {
      name  = "subscription-service"
      image = "${local.gar_url}/subscription-service:latest"

      ports {
        container_port = 8080
      }

      resources {
        limits   = { cpu = "1", memory = "256Mi" }
        cpu_idle = true
      }

      env {
        name  = "ENVIRONMENT"
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
        value = "subscriptions_db"
      }
      env {
        name  = "DB_USER"
        value = "subscriptions_user"
      }
      env {
        name  = "DB_SSLMODE"
        value = "disable"
      }
      env {
        name  = "TENANT_SERVICE_URL"
        value = google_cloud_run_v2_service.tenant_service.uri
      }

      env {
        name = "DB_PASSWORD"
        value_source {
          secret_key_ref {
            secret  = "subscriptions-db-password"
            version = "latest"
          }
        }
      }
      env {
        name = "STRIPE_SECRET_KEY"
        value_source {
          secret_key_ref {
            secret  = "stripe-secret-key"
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

# --- Document Service ---
resource "google_cloud_run_v2_service" "document_service" {
  name                = "document-service"
  location            = var.region
  deletion_protection = false

  template {
    service_account = local.sa_emails["document-service"]

    scaling {
      min_instance_count = 0
      max_instance_count = 5
    }

    containers {
      name  = "document-service"
      image = "${local.gar_url}/document-service:latest"

      ports {
        container_port = 8080
      }

      resources {
        limits   = { cpu = "1", memory = "256Mi" }
        cpu_idle = true
      }

      env {
        name  = "ENVIRONMENT"
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
        value = "documents_db"
      }
      env {
        name  = "DB_USER"
        value = "documents_user"
      }
      env {
        name  = "DB_SSLMODE"
        value = "disable"
      }

      env {
        name = "DB_PASSWORD"
        value_source {
          secret_key_ref {
            secret  = "documents-db-password"
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

# --- QR Service ---
resource "google_cloud_run_v2_service" "qr_service" {
  name                = "qr-service"
  location            = var.region
  deletion_protection = false

  template {
    service_account = local.sa_emails["qr-service"]

    scaling {
      min_instance_count = 0
      max_instance_count = 3
    }

    containers {
      name  = "qr-service"
      image = "${local.gar_url}/qr-service:latest"

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

# --- Analytics Service ---
resource "google_cloud_run_v2_service" "analytics_service" {
  name                = "analytics-service"
  location            = var.region
  deletion_protection = false

  template {
    service_account = local.sa_emails["analytics-service"]

    scaling {
      min_instance_count = 0
      max_instance_count = 3
    }

    containers {
      name  = "analytics-service"
      image = "${local.gar_url}/analytics-service:latest"

      ports {
        container_port = 8091
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
        value = "analytics_db"
      }
      env {
        name  = "DB_USER"
        value = "analytics_user"
      }
      env {
        name  = "DB_SSL_MODE"
        value = "disable"
      }

      env {
        name = "DB_PASSWORD"
        value_source {
          secret_key_ref {
            secret  = "analytics-db-password"
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

# --- Verification Service ---
resource "google_cloud_run_v2_service" "verification_service" {
  name                = "verification-service"
  location            = var.region
  deletion_protection = false

  template {
    service_account = local.sa_emails["verification-service"]

    scaling {
      min_instance_count = 0
      max_instance_count = 5
    }

    containers {
      name  = "verification-service"
      image = "${local.gar_url}/verification-service:latest"

      ports {
        container_port = 8080
      }

      resources {
        limits   = { cpu = "1", memory = "256Mi" }
        cpu_idle = true
      }

      env {
        name  = "ENVIRONMENT"
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
        value = "verifications_db"
      }
      env {
        name  = "DB_USER"
        value = "verifications_user"
      }
      env {
        name  = "DB_SSLMODE"
        value = "disable"
      }
      env {
        name  = "NOTIFICATION_SERVICE_URL"
        value = google_cloud_run_v2_service.notification_service.uri
      }

      env {
        name = "DB_PASSWORD"
        value_source {
          secret_key_ref {
            secret  = "verifications-db-password"
            version = "latest"
          }
        }
      }
      env {
        name = "API_KEY"
        value_source {
          secret_key_ref {
            secret  = "shared-internal-service-key"
            version = "latest"
          }
        }
      }
      env {
        name = "ENCRYPTION_KEY"
        value_source {
          secret_key_ref {
            secret  = "verification-encryption-key"
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

# --- Feature Flags Service ---
resource "google_cloud_run_v2_service" "feature_flags" {
  name                = "feature-flags-service"
  location            = var.region
  deletion_protection = false

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
        limits   = { cpu = "1", memory = "256Mi" }
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

# --- Location Service ---
resource "google_cloud_run_v2_service" "location_service" {
  name                = "location-service"
  location            = var.region
  deletion_protection = false

  template {
    service_account = local.sa_emails["location-service"]

    scaling {
      min_instance_count = 0
      max_instance_count = 3
    }

    containers {
      name  = "location-service"
      image = "${local.gar_url}/location-service:latest"

      ports {
        container_port = 8080
      }

      resources {
        limits   = { cpu = "1", memory = "256Mi" }
        cpu_idle = true
      }

      env {
        name  = "ENVIRONMENT"
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
        value = "location_db"
      }
      env {
        name  = "DB_USER"
        value = "location_user"
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
            secret  = "location-db-password"
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

# --- Tenant Router Service ---
resource "google_cloud_run_v2_service" "tenant_router_service" {
  name                = "tenant-router-service"
  location            = var.region
  deletion_protection = false

  template {
    service_account = local.sa_emails["tenant-router-service"]

    scaling {
      min_instance_count = 0
      max_instance_count = 3
    }

    containers {
      name  = "tenant-router-service"
      image = "${local.gar_url}/tenant-router-service:latest"

      ports {
        container_port = 8089
      }

      resources {
        limits   = { cpu = "1", memory = "256Mi" }
        cpu_idle = true
      }

      env {
        name  = "GCP_PROJECT_ID"
        value = var.project_id
      }
      env {
        name  = "PLATFORM_DOMAIN"
        value = "tesserix.app"
      }
      env {
        name  = "BASE_DOMAIN"
        value = "mark8ly.com"
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
        value = "tenant_router_db"
      }
      env {
        name  = "DB_USER"
        value = "tenant_router_user"
      }
      env {
        name  = "DB_SSLMODE"
        value = "disable"
      }
      env {
        name  = "NOTIFICATION_SERVICE_URL"
        value = google_cloud_run_v2_service.notification_service.uri
      }
      env {
        name  = "AUDIT_SERVICE_URL"
        value = google_cloud_run_v2_service.audit_service.uri
      }

      env {
        name = "DB_PASSWORD"
        value_source {
          secret_key_ref {
            secret  = "tenant-router-db-password"
            version = "latest"
          }
        }
      }
      env {
        name = "API_KEY"
        value_source {
          secret_key_ref {
            secret  = "shared-internal-service-key"
            version = "latest"
          }
        }
      }
      env {
        name = "CLOUDFLARE_API_TOKEN"
        value_source {
          secret_key_ref {
            secret  = "cloudflare-api-token"
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

# --- Marketplace Onboarding (Next.js) ---
resource "google_cloud_run_v2_service" "marketplace_onboarding" {
  name                = "marketplace-onboarding"
  location            = var.region
  deletion_protection = false

  template {
    service_account = local.sa_emails["marketplace-onboarding"]

    scaling {
      min_instance_count = 0
      max_instance_count = 5
    }

    containers {
      name  = "marketplace-onboarding"
      image = "${local.gar_url}/marketplace-onboarding:latest"

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
        name  = "AUTH_BFF_URL"
        value = google_cloud_run_v2_service.auth_bff.uri
      }
      env {
        name  = "TENANT_SERVICE_URL"
        value = google_cloud_run_v2_service.tenant_service.uri
      }
      env {
        name  = "LOCATION_SERVICE_URL"
        value = google_cloud_run_v2_service.location_service.uri
      }
      env {
        name  = "VERIFICATION_SERVICE_URL"
        value = google_cloud_run_v2_service.verification_service.uri
      }
      env {
        name  = "TENANT_ROUTER_URL"
        value = google_cloud_run_v2_service.tenant_router_service.uri
      }
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

# =============================================================================
# PUBLIC ACCESS — Backend services use app-level auth (JWT), not Cloud Run IAM.
# Allow unauthenticated at Cloud Run level for all backend services.
# =============================================================================
locals {
  public_services = {
    subscription          = google_cloud_run_v2_service.subscription_service.name
    notification          = google_cloud_run_v2_service.notification_service.name
    document              = google_cloud_run_v2_service.document_service.name
    verification          = google_cloud_run_v2_service.verification_service.name
    analytics             = google_cloud_run_v2_service.analytics_service.name
    status                = google_cloud_run_v2_service.status_service.name
    location              = google_cloud_run_v2_service.location_service.name
    tenant_router         = google_cloud_run_v2_service.tenant_router_service.name
    marketplace_onboarding = google_cloud_run_v2_service.marketplace_onboarding.name
  }
}

resource "google_cloud_run_service_iam_member" "public_access" {
  for_each = local.public_services
  service  = each.value
  location = var.region
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# --- Status Service ---

resource "google_cloud_run_v2_service" "status_service" {
  name                = "status-service"
  location            = var.region
  deletion_protection = false

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
