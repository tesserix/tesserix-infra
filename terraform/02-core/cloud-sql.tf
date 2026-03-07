# =============================================================================
# CLOUD SQL — Single instance, per-service databases + users
# =============================================================================
# Current data: 230 MB across 28 databases. db-f1-micro handles this easily.
# Upgrade path: db-f1-micro → db-g1-small → db-custom when traffic grows.
# =============================================================================

resource "google_sql_database_instance" "main" {
  name                = "tesserix-main"
  database_version    = "POSTGRES_15"
  region              = var.region
  deletion_protection = true

  depends_on = [google_service_networking_connection.private_vpc]

  settings {
    tier              = "db-f1-micro"
    availability_type = "ZONAL"
    disk_size         = 10
    disk_type         = "PD_SSD"
    disk_autoresize   = true

    ip_configuration {
      ipv4_enabled                                  = true
      private_network                               = google_compute_network.main.id
      enable_private_path_for_google_cloud_services = true
    }

    backup_configuration {
      enabled                        = true
      point_in_time_recovery_enabled = true
      start_time                     = "03:00"
      transaction_log_retention_days = 7
      backup_retention_settings {
        retained_backups = 7
      }
    }

    maintenance_window {
      day          = 7
      hour         = 4
      update_track = "stable"
    }

    database_flags {
      name  = "max_connections"
      value = "50"
    }
  }
}

# --- Databases ---
locals {
  platform_databases = [
    "openfga_db",
    "audit_db",
    "notifications_db",
    "tenants_db",
    "settings_db",
    "subscriptions_db",
    "documents_db",
    "tickets_db",
    "analytics_db",
    "verifications_db",
    "location_db",
    "tenant_router_db",
  ]

  marketplace_databases = [
    "mp_products_db",
    "mp_orders_db",
    "mp_payments_db",
    "mp_inventory_db",
    "mp_shipping_db",
    "mp_categories_db",
    "mp_coupons_db",
    "mp_reviews_db",
    "mp_vendors_db",
    "mp_customers_db",
    "mp_onboarding_db",
  ]

  all_databases = concat(local.platform_databases, local.marketplace_databases)
}

resource "google_sql_database" "databases" {
  for_each = toset(local.all_databases)
  name     = each.value
  instance = google_sql_database_instance.main.name
}

# --- Per-service users with random passwords ---
resource "random_password" "db_passwords" {
  for_each = toset(local.all_databases)
  length   = 32
  special  = false
}

resource "google_sql_user" "users" {
  for_each = toset(local.all_databases)
  name     = replace(each.value, "_db", "_user")
  instance = google_sql_database_instance.main.name
  password = random_password.db_passwords[each.value].result
}

# --- Store passwords in Secret Manager ---
resource "google_secret_manager_secret" "db_passwords" {
  for_each  = toset(local.all_databases)
  secret_id = replace(each.value, "_db", "-db-password") # audit_db → audit-db-password

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "db_passwords" {
  for_each    = google_secret_manager_secret.db_passwords
  secret      = each.value.id
  secret_data = random_password.db_passwords[each.key].result
}
