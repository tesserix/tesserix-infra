# =============================================================================
# SERVICE CONFIGURATION — locals-based map driving for_each Cloud Run resources
# =============================================================================
# Special services (openfga, auth-bff, tesserix-home, marketplace-onboarding,
# marketplace-admin, status-service) are defined individually in cloud-run-special.tf because
# they have unique images, env shapes, or resource limits that don't fit the
# standard template.
# =============================================================================

locals {
  # ---------------------------------------------------------------------------
  # Standard Go backend services with a Cloud SQL sidecar.
  #
  # Schema per entry:
  #   image          - container image override; "" = use GAR default
  #                    (set to placeholder for services without a CI build yet)
  #   db_name        - PostgreSQL database name (DB_NAME)
  #   db_user        - PostgreSQL user (DB_USER)
  #   db_ssl_key     - env var name for the SSL mode flag (almost always
  #                    "DB_SSLMODE"; analytics-service uses "DB_SSL_MODE")
  #   port           - container port (default 8080; override per service)
  #   max_instances  - Cloud Run max instance count
  #   memory         - container memory limit (default "256Mi")
  #   env_project_id - emit ENVIRONMENT=production + GCP_PROJECT_ID=<project>
  #   env_app_env    - emit APP_ENV=production (tickets-service only)
  #   env_platform   - emit GCP_PROJECT_ID only (tenant-router-service)
  #   openfga_url    - true → inject OPENFGA_URL from the openfga special svc
  #   service_urls   - map of ENV_VAR_NAME → service key in local.all_service_uris
  #                    (service-to-service references resolved at plan time)
  #   url_suffix     - optional path suffix appended to a service URI
  #                    (not used in standard services; kept for completeness)
  #   secrets        - map of ENV_VAR_NAME → Secret Manager secret name
  # ---------------------------------------------------------------------------

  # Placeholder image for services that haven't had their first CI build yet.
  placeholder_image = "gcr.io/cloudrun/hello:latest"

  standard_db_services = {

    "audit-service" = {
      image          = ""
      db_name        = "audit_db"
      db_user        = "audit_user"
      db_ssl_key     = "DB_SSLMODE"
      port           = 8080
      max_instances  = 5
      memory         = "256Mi"
      env_project_id = false
      env_app_env    = false
      env_platform   = false
      openfga_url    = true
      service_urls = {
        "TENANT_REGISTRY_URL" = "tenant-service"
      }
      secrets = {
        "DB_PASSWORD"     = "audit-db-password"
        "OPENFGA_API_KEY" = "openfga-preshared-key"
      }
    }

    "tenant-service" = {
      image          = ""
      db_name        = "tenants_db"
      db_user        = "tenants_user"
      db_ssl_key     = "DB_SSLMODE"
      port           = 8080
      max_instances  = 5
      memory         = "256Mi"
      env_project_id = false
      env_app_env    = false
      env_platform   = false
      openfga_url    = true
      service_urls   = {}
      # Service URLs (NOTIFICATION_SERVICE_URL, VERIFICATION_SERVICE_URL, etc.)
      # are set via gcloud/CI — cannot use Terraform refs from base tier.
      secrets = {
        "DB_PASSWORD"          = "tenants-db-password"
        "OPENFGA_API_KEY"      = "openfga-preshared-key"
        "NOTIFICATION_API_KEY" = "shared-internal-service-key"
        "VERIFICATION_API_KEY" = "shared-internal-service-key"
      }
    }

    "notification-service" = {
      image          = ""
      db_name        = "notifications_db"
      db_user        = "notifications_user"
      db_ssl_key     = "DB_SSLMODE"
      port           = 8080
      max_instances  = 5
      memory         = "256Mi"
      env_project_id = false
      env_app_env    = false
      env_platform   = false
      openfga_url    = false
      service_urls   = {}
      secrets = {
        "DB_PASSWORD"      = "notifications-db-password"
        "SENDGRID_API_KEY" = "sendgrid-api-key"
      }
    }

    "tickets-service" = {
      image          = ""
      db_name        = "tickets_db"
      db_user        = "tickets_user"
      db_ssl_key     = "DB_SSLMODE"
      port           = 8080
      max_instances  = 5
      memory         = "256Mi"
      env_project_id = true  # emits ENVIRONMENT + GCP_PROJECT_ID
      env_app_env    = true  # also emits APP_ENV
      env_platform   = false
      openfga_url    = true
      service_urls = {
        "NOTIFICATION_SERVICE_URL" = "notification-service"
        "TENANT_SERVICE_URL"       = "tenant-service"
      }
      secrets = {
        "DB_PASSWORD"                  = "tickets-db-password"
        "OPENFGA_API_KEY"              = "openfga-preshared-key"
        "OPENFGA_MARKETPLACE_STORE_ID" = "openfga-marketplace-store-id"
      }
    }

    "subscription-service" = {
      image          = ""
      db_name        = "subscriptions_db"
      db_user        = "subscriptions_user"
      db_ssl_key     = "DB_SSLMODE"
      port           = 8080
      max_instances  = 5
      memory         = "256Mi"
      env_project_id = true  # emits ENVIRONMENT + GCP_PROJECT_ID
      env_app_env    = false
      env_platform   = false
      openfga_url    = false
      service_urls = {
        "TENANT_SERVICE_URL" = "tenant-service"
      }
      secrets = {
        "DB_PASSWORD"           = "subscriptions-db-password"
        "STRIPE_SECRET_KEY"     = "stripe-secret-key"
        "STRIPE_WEBHOOK_SECRET" = "stripe-webhook-secret"
      }
    }

    "document-service" = {
      image          = ""
      db_name        = "documents_db"
      db_user        = "documents_user"
      db_ssl_key     = "DB_SSLMODE"
      port           = 8080
      max_instances  = 5
      memory         = "256Mi"
      env_project_id = true  # emits ENVIRONMENT + GCP_PROJECT_ID
      env_app_env    = false
      env_platform   = false
      openfga_url    = false
      service_urls   = {}
      secrets = {
        "DB_PASSWORD" = "documents-db-password"
      }
    }

    "location-service" = {
      image          = local.placeholder_image
      db_name        = "location_db"
      db_user        = "location_user"
      db_ssl_key     = "DB_SSLMODE"
      port           = 8080
      max_instances  = 3
      memory         = "256Mi"
      env_project_id = true  # emits ENVIRONMENT + GCP_PROJECT_ID
      env_app_env    = false
      env_platform   = false
      openfga_url    = true
      service_urls   = {}
      secrets = {
        "DB_PASSWORD"                  = "location-db-password"
        "OPENFGA_API_KEY"              = "openfga-preshared-key"
        "OPENFGA_MARKETPLACE_STORE_ID" = "openfga-marketplace-store-id"
      }
    }

    "verification-service" = {
      image          = ""
      db_name        = "verifications_db"
      db_user        = "verifications_user"
      db_ssl_key     = "DB_SSLMODE"
      port           = 8080
      max_instances  = 5
      memory         = "256Mi"
      env_project_id = true  # emits ENVIRONMENT + GCP_PROJECT_ID
      env_app_env    = false
      env_platform   = false
      openfga_url    = false
      service_urls = {
        "NOTIFICATION_SERVICE_URL" = "notification-service"
      }
      secrets = {
        "DB_PASSWORD"      = "verifications-db-password"
        "API_KEY"          = "shared-internal-service-key"
        "ENCRYPTION_KEY"   = "verification-encryption-key"
      }
    }

    "settings-service" = {
      image          = local.placeholder_image
      db_name        = "settings_db"
      db_user        = "settings_user"
      db_ssl_key     = "DB_SSLMODE"
      port           = 8080
      max_instances  = 3
      memory         = "256Mi"
      env_project_id = true
      env_app_env    = true
      env_platform   = false
      openfga_url    = true
      service_urls   = {}
      secrets = {
        "DB_PASSWORD"              = "settings-db-password"
        "OPENFGA_API_KEY"          = "openfga-preshared-key"
        "OPENFGA_PLATFORM_STORE_ID" = "openfga-platform-store-id"
      }
    }

    # -----------------------------------------------------------------------
    # MARKETPLACE GO BACKEND SERVICES
    # -----------------------------------------------------------------------

    "mp-products" = {
      image          = local.placeholder_image
      db_name        = "mp_products_db"
      db_user        = "mp_products_user"
      db_ssl_key     = "DB_SSLMODE"
      port           = 8080
      max_instances  = 5
      memory         = "256Mi"
      env_project_id = true
      env_app_env    = false
      env_platform   = false
      openfga_url    = true
      service_urls = {
        "DOCUMENT_SERVICE_URL"  = "document-service"
        "INVENTORY_SERVICE_URL" = "mp-inventory"
        "VENDOR_SERVICE_URL"    = "mp-vendors"
        "APPROVAL_SERVICE_URL"  = "mp-approvals"
      }
      # CATEGORIES_SERVICE_URL: mp-categories is also dependent (has service_urls),
      # so it can't be resolved here. Will be empty — add Pub/Sub or set manually.
      secrets = {
        "DB_PASSWORD"                  = "mp_products-db-password"
        "OPENFGA_API_KEY"              = "openfga-preshared-key"
        "OPENFGA_MARKETPLACE_STORE_ID" = "openfga-marketplace-store-id"
      }
    }

    "mp-payments" = {
      image          = local.placeholder_image
      db_name        = "mp_payments_db"
      db_user        = "mp_payments_user"
      db_ssl_key     = "DB_SSLMODE"
      port           = 8080
      max_instances  = 5
      memory         = "256Mi"
      env_project_id = true
      env_app_env    = false
      env_platform   = false
      openfga_url    = true
      service_urls = {
        "NOTIFICATION_SERVICE_URL" = "notification-service"
        "TENANT_SERVICE_URL"       = "tenant-service"
        "APPROVAL_SERVICE_URL"     = "mp-approvals"
      }
      # ORDERS_SERVICE_URL: mp-orders is tier3 (can't reference from dependent).
      # Payment→orders notifications should use Pub/Sub events instead.
      secrets = {
        "DB_PASSWORD"                  = "mp_payments-db-password"
        "STRIPE_SECRET_KEY"            = "stripe-secret-key"
        "STRIPE_WEBHOOK_SECRET"        = "stripe-webhook-secret"
        "OPENFGA_API_KEY"              = "openfga-preshared-key"
        "OPENFGA_MARKETPLACE_STORE_ID" = "openfga-marketplace-store-id"
      }
    }

    "mp-inventory" = {
      image          = local.placeholder_image
      db_name        = "mp_inventory_db"
      db_user        = "mp_inventory_user"
      db_ssl_key     = "DB_SSLMODE"
      port           = 8088
      max_instances  = 5
      memory         = "256Mi"
      env_project_id = true
      env_app_env    = false
      env_platform   = false
      openfga_url    = true
      service_urls   = {}
      secrets = {
        "DB_PASSWORD"                  = "mp_inventory-db-password"
        "OPENFGA_API_KEY"              = "openfga-preshared-key"
        "OPENFGA_MARKETPLACE_STORE_ID" = "openfga-marketplace-store-id"
      }
    }

    "mp-shipping" = {
      image          = local.placeholder_image
      db_name        = "mp_shipping_db"
      db_user        = "mp_shipping_user"
      db_ssl_key     = "DB_SSLMODE"
      port           = 8080
      max_instances  = 3
      memory         = "256Mi"
      env_project_id = true
      env_app_env    = false
      env_platform   = false
      openfga_url    = true
      service_urls   = {}
      secrets = {
        "DB_PASSWORD"                  = "mp_shipping-db-password"
        "OPENFGA_API_KEY"              = "openfga-preshared-key"
        "OPENFGA_MARKETPLACE_STORE_ID" = "openfga-marketplace-store-id"
      }
    }

    "mp-categories" = {
      image          = local.placeholder_image
      db_name        = "mp_categories_db"
      db_user        = "mp_categories_user"
      db_ssl_key     = "DB_SSLMODE"
      port           = 8080
      max_instances  = 3
      memory         = "256Mi"
      env_project_id = true
      env_app_env    = false
      env_platform   = false
      openfga_url    = true
      service_urls = {
        "APPROVAL_SERVICE_URL" = "mp-approvals"
      }
      secrets = {
        "DB_PASSWORD"                  = "mp_categories-db-password"
        "OPENFGA_API_KEY"              = "openfga-preshared-key"
        "OPENFGA_MARKETPLACE_STORE_ID" = "openfga-marketplace-store-id"
      }
    }

    "mp-coupons" = {
      image          = local.placeholder_image
      db_name        = "mp_coupons_db"
      db_user        = "mp_coupons_user"
      db_ssl_key     = "DB_SSLMODE"
      port           = 8080
      max_instances  = 3
      memory         = "256Mi"
      env_project_id = true
      env_app_env    = false
      env_platform   = false
      openfga_url    = true
      service_urls   = {}
      secrets = {
        "DB_PASSWORD"                  = "mp_coupons-db-password"
        "OPENFGA_API_KEY"              = "openfga-preshared-key"
        "OPENFGA_MARKETPLACE_STORE_ID" = "openfga-marketplace-store-id"
      }
    }

    "mp-reviews" = {
      image          = local.placeholder_image
      db_name        = "mp_reviews_db"
      db_user        = "mp_reviews_user"
      db_ssl_key     = "DB_SSLMODE"
      port           = 8080
      max_instances  = 3
      memory         = "256Mi"
      env_project_id = true
      env_app_env    = false
      env_platform   = false
      openfga_url    = true
      service_urls   = {}
      secrets = {
        "DB_PASSWORD"                  = "mp_reviews-db-password"
        "OPENFGA_API_KEY"              = "openfga-preshared-key"
        "OPENFGA_MARKETPLACE_STORE_ID" = "openfga-marketplace-store-id"
      }
    }

    "mp-vendors" = {
      image          = local.placeholder_image
      db_name        = "mp_vendors_db"
      db_user        = "mp_vendors_user"
      db_ssl_key     = "DB_SSLMODE"
      port           = 8080
      max_instances  = 5
      memory         = "256Mi"
      env_project_id = true
      env_app_env    = false
      env_platform   = false
      openfga_url    = true
      service_urls   = {}
      secrets = {
        "DB_PASSWORD"                  = "mp_vendors-db-password"
        "OPENFGA_API_KEY"              = "openfga-preshared-key"
        "OPENFGA_MARKETPLACE_STORE_ID" = "openfga-marketplace-store-id"
      }
    }

    "mp-customers" = {
      image          = local.placeholder_image
      db_name        = "mp_customers_db"
      db_user        = "mp_customers_user"
      db_ssl_key     = "DB_SSLMODE"
      port           = 8080
      max_instances  = 5
      memory         = "256Mi"
      env_project_id = true
      env_app_env    = false
      env_platform   = false
      openfga_url    = true
      service_urls = {
        "NOTIFICATION_SERVICE_URL" = "notification-service"
        "TENANT_SERVICE_URL"       = "tenant-service"
      }
      secrets = {
        "DB_PASSWORD"                  = "mp_customers-db-password"
        "OPENFGA_API_KEY"              = "openfga-preshared-key"
        "OPENFGA_MARKETPLACE_STORE_ID" = "openfga-marketplace-store-id"
      }
    }

    "mp-staff" = {
      image          = local.placeholder_image
      db_name        = "mp_staff_db"
      db_user        = "mp_staff_user"
      db_ssl_key     = "DB_SSLMODE"
      port           = 8080
      max_instances  = 5
      memory         = "256Mi"
      env_project_id = true
      env_app_env    = false
      env_platform   = false
      openfga_url    = true
      service_urls   = {}
      secrets = {
        "DB_PASSWORD"                  = "mp_staff-db-password"
        "OPENFGA_API_KEY"              = "openfga-preshared-key"
        "OPENFGA_MARKETPLACE_STORE_ID" = "openfga-marketplace-store-id"
      }
    }

    "mp-content" = {
      image          = local.placeholder_image
      db_name        = "mp_content_db"
      db_user        = "mp_content_user"
      db_ssl_key     = "DB_SSLMODE"
      port           = 8080
      max_instances  = 3
      memory         = "256Mi"
      env_project_id = true
      env_app_env    = false
      env_platform   = false
      openfga_url    = true
      service_urls   = {}
      secrets = {
        "DB_PASSWORD"                  = "mp_content-db-password"
        "OPENFGA_API_KEY"              = "openfga-preshared-key"
        "OPENFGA_MARKETPLACE_STORE_ID" = "openfga-marketplace-store-id"
      }
    }

    "mp-approvals" = {
      image          = local.placeholder_image
      db_name        = "mp_approvals_db"
      db_user        = "mp_approvals_user"
      db_ssl_key     = "DB_SSLMODE"
      port           = 8099
      max_instances  = 3
      memory         = "256Mi"
      env_project_id = true
      env_app_env    = false
      env_platform   = false
      openfga_url    = true
      service_urls   = {}
      secrets = {
        "DB_PASSWORD"                  = "mp_approvals-db-password"
        "OPENFGA_API_KEY"              = "openfga-preshared-key"
        "OPENFGA_MARKETPLACE_STORE_ID" = "openfga-marketplace-store-id"
      }
    }

    "mp-gift-cards" = {
      image          = local.placeholder_image
      db_name        = "mp_gift_cards_db"
      db_user        = "mp_gift_cards_user"
      db_ssl_key     = "DB_SSLMODE"
      port           = 8080
      max_instances  = 3
      memory         = "256Mi"
      env_project_id = true
      env_app_env    = false
      env_platform   = false
      openfga_url    = true
      service_urls   = {}
      secrets = {
        "DB_PASSWORD"                  = "mp_gift_cards-db-password"
        "OPENFGA_API_KEY"              = "openfga-preshared-key"
        "OPENFGA_MARKETPLACE_STORE_ID" = "openfga-marketplace-store-id"
      }
    }

    "mp-tax" = {
      image          = local.placeholder_image
      db_name        = "mp_tax_db"
      db_user        = "mp_tax_user"
      db_ssl_key     = "DB_SSLMODE"
      port           = 8080
      max_instances  = 3
      memory         = "256Mi"
      env_project_id = true
      env_app_env    = false
      env_platform   = false
      openfga_url    = true
      service_urls   = {}
      secrets = {
        "DB_PASSWORD"                  = "mp_tax-db-password"
        "OPENFGA_API_KEY"              = "openfga-preshared-key"
        "OPENFGA_MARKETPLACE_STORE_ID" = "openfga-marketplace-store-id"
      }
    }

    # analytics-service: non-standard port (8091) and DB_SSL_MODE key name
    "analytics-service" = {
      image          = ""
      db_name        = "analytics_db"
      db_user        = "analytics_user"
      db_ssl_key     = "DB_SSL_MODE" # intentional — differs from other services
      port           = 8091
      max_instances  = 3
      memory         = "256Mi"
      env_project_id = false
      env_app_env    = false
      env_platform   = false
      openfga_url    = false
      service_urls   = {}
      secrets = {
        "DB_PASSWORD" = "analytics-db-password"
      }
    }

    "mp-orders" = {
      image          = local.placeholder_image
      db_name        = "mp_orders_db"
      db_user        = "mp_orders_user"
      db_ssl_key     = "DB_SSLMODE"
      port           = 8080
      max_instances  = 5
      memory         = "256Mi"
      env_project_id = true
      env_app_env    = false
      env_platform   = false
      openfga_url    = true
      service_urls = {
        "INVENTORY_SERVICE_URL"    = "mp-inventory"
        "SHIPPING_SERVICE_URL"     = "mp-shipping"
        "NOTIFICATION_SERVICE_URL" = "notification-service"
        "TAX_SERVICE_URL"          = "mp-tax"
        "DOCUMENT_SERVICE_URL"     = "document-service"
        "APPROVAL_SERVICE_URL"     = "mp-approvals"
        "TENANT_SERVICE_URL"       = "tenant-service"
        "SETTINGS_SERVICE_URL"     = "settings-service"
      }
      cross_dependent_urls = {
        "PAYMENT_SERVICE_URL"   = "mp-payments"
        "PRODUCTS_SERVICE_URL"  = "mp-products"
        "CUSTOMERS_SERVICE_URL" = "mp-customers"
      }
      secrets = {
        "DB_PASSWORD"                  = "mp_orders-db-password"
        "OPENFGA_API_KEY"              = "openfga-preshared-key"
        "OPENFGA_MARKETPLACE_STORE_ID" = "openfga-marketplace-store-id"
      }
    }

    "mp-marketing" = {
      image          = local.placeholder_image
      db_name        = "mp_marketing_db"
      db_user        = "mp_marketing_user"
      db_ssl_key     = "DB_SSLMODE"
      port           = 8080
      max_instances  = 3
      memory         = "256Mi"
      env_project_id = true
      env_app_env    = false
      env_platform   = false
      openfga_url    = true
      service_urls = {
        "NOTIFICATION_SERVICE_URL" = "notification-service"
      }
      secrets = {
        "DB_PASSWORD"                  = "mp_marketing-db-password"
        "OPENFGA_API_KEY"              = "openfga-preshared-key"
        "OPENFGA_MARKETPLACE_STORE_ID" = "openfga-marketplace-store-id"
      }
    }

    "mp-connector" = {
      image          = local.placeholder_image
      db_name        = "mp_connector_db"
      db_user        = "mp_connector_user"
      db_ssl_key     = "DB_SSLMODE"
      port           = 8080
      max_instances  = 3
      memory         = "256Mi"
      env_project_id = true
      env_app_env    = false
      env_platform   = false
      openfga_url    = true
      service_urls = {
        "INVENTORY_SERVICE_URL" = "mp-inventory"
      }
      cross_dependent_urls = {
        "PRODUCTS_SERVICE_URL" = "mp-products"
      }
      secrets = {
        "DB_PASSWORD"                  = "mp_connector-db-password"
        "OPENFGA_API_KEY"              = "openfga-preshared-key"
        "OPENFGA_MARKETPLACE_STORE_ID" = "openfga-marketplace-store-id"
      }
    }

    # tenant-router-service: non-standard port (8089), custom domain envs,
    # GCP_PROJECT_ID only (no ENVIRONMENT flag), references two peer services
    "tenant-router-service" = {
      image          = ""
      db_name        = "tenant_router_db"
      db_user        = "tenant_router_user"
      db_ssl_key     = "DB_SSLMODE"
      port           = 8089
      max_instances  = 3
      memory         = "256Mi"
      env_project_id = false
      env_app_env    = false
      env_platform   = true  # emits GCP_PROJECT_ID only (no ENVIRONMENT)
      openfga_url    = false
      service_urls = {
        "NOTIFICATION_SERVICE_URL" = "notification-service"
        "AUDIT_SERVICE_URL"        = "audit-service"
      }
      secrets = {
        "DB_PASSWORD"          = "tenant_router-db-password"
        "API_KEY"              = "shared-internal-service-key"
        "CLOUDFLARE_API_TOKEN" = "cloudflare-api-token"
      }
    }
  }

  # ---------------------------------------------------------------------------
  # Simple stateless services: no DB, no sidecar.
  # Schema: port, max_instances, memory, secrets map.
  # ---------------------------------------------------------------------------
  simple_services = {

    "qr-service" = {
      image         = ""
      port          = 8080
      max_instances = 3
      memory        = "256Mi"
      secrets       = {}
    }

    "feature-flags-service" = {
      image         = ""
      port          = 8080
      max_instances = 3
      memory        = "256Mi"
      secrets = {
        "GROWTHBOOK_API_KEY" = "growthbook-api-key"
      }
    }
  }

  # ---------------------------------------------------------------------------
  # Three-tier split to avoid Terraform for_each self-referencing cycles.
  #   base:      no service_urls, no cross_dependent_urls
  #   dependent: service_urls (→ base), no cross_dependent_urls
  #   tier3:     service_urls (→ base) + cross_dependent_urls (→ dependent)
  # ---------------------------------------------------------------------------
  base_db_services      = { for k, v in local.standard_db_services : k => v if length(v.service_urls) == 0 }
  dependent_db_services = { for k, v in local.standard_db_services : k => v if length(v.service_urls) > 0 && length(lookup(v, "cross_dependent_urls", {})) == 0 }
  tier3_db_services     = { for k, v in local.standard_db_services : k => v if length(lookup(v, "cross_dependent_urls", {})) > 0 }

  # ---------------------------------------------------------------------------
  # Public-access IAM: services that allow allUsers at the Cloud Run layer.
  # App-level GIP JWT auth handles actual security for backend services.
  # ---------------------------------------------------------------------------
  # Only publicly reachable services — backend Go services are NOT public.
  # App-level GIP JWT auth + Cloud Run IAM handle security for internal services.
  public_services = {
    "auth-bff"               = "auth-bff"
    "marketplace-onboarding" = "marketplace-onboarding"
    "marketplace-admin"      = "marketplace-admin"
    "mp-storefront"          = "mp-storefront"
    "status-service"         = "status-service"
    "tesserix-home"          = "tesserix-home"
  }
}
