# =============================================================================
# PUB/SUB — Async event messaging (replaces NATS)
# =============================================================================
# Cost: $0 (free tier: 10 Gi/month)
# Pattern: services publish events → push subscriptions call Cloud Run endpoints
# =============================================================================

# --- Audit Events ---
resource "google_pubsub_topic" "audit_events" {
  name                       = "tesserix-audit-events"
  message_retention_duration = "604800s" # 7 days
}

resource "google_pubsub_topic" "audit_events_dlq" {
  name = "tesserix-audit-events-dlq"
}

resource "google_pubsub_subscription" "audit_push" {
  name  = "audit-service-push"
  topic = google_pubsub_topic.audit_events.id

  push_config {
    push_endpoint = "${google_cloud_run_v2_service.base["audit-service"].uri}/events"
    oidc_token {
      service_account_email = data.terraform_remote_state.iam.outputs.service_account_emails["audit-service"]
    }
  }

  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.audit_events_dlq.id
    max_delivery_attempts = 5
  }

  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }
}

# --- Notification Events ---
resource "google_pubsub_topic" "notification_events" {
  name                       = "tesserix-notification-events"
  message_retention_duration = "604800s"
}

resource "google_pubsub_topic" "notification_events_dlq" {
  name = "tesserix-notification-events-dlq"
}

resource "google_pubsub_subscription" "notification_push" {
  name  = "notification-service-push"
  topic = google_pubsub_topic.notification_events.id

  push_config {
    push_endpoint = "${google_cloud_run_v2_service.base["notification-service"].uri}/events/push"
    oidc_token {
      service_account_email = data.terraform_remote_state.iam.outputs.service_account_emails["notification-service"]
    }
  }

  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.notification_events_dlq.id
    max_delivery_attempts = 5
  }

  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }
}

# --- Tenant Events ---
resource "google_pubsub_topic" "tenant_events" {
  name                       = "tesserix-tenant-events"
  message_retention_duration = "604800s" # 7 days
}

resource "google_pubsub_topic" "tenant_events_dlq" {
  name = "tesserix-tenant-events-dlq"
}

resource "google_pubsub_subscription" "subscription_service_tenant_push" {
  name  = "subscription-service-tenant-push"
  topic = google_pubsub_topic.tenant_events.id

  push_config {
    push_endpoint = "${google_cloud_run_v2_service.base["subscription-service"].uri}/events/push"
    oidc_token {
      service_account_email = data.terraform_remote_state.iam.outputs.service_account_emails["subscription-service"]
    }
  }

  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.tenant_events_dlq.id
    max_delivery_attempts = 5
  }

  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }
}

resource "google_pubsub_subscription" "notification_service_tenant_push" {
  name  = "notification-service-tenant-push"
  topic = google_pubsub_topic.tenant_events.id

  push_config {
    push_endpoint = "${google_cloud_run_v2_service.base["notification-service"].uri}/events/push"
    oidc_token {
      service_account_email = data.terraform_remote_state.iam.outputs.service_account_emails["notification-service"]
    }
  }

  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.tenant_events_dlq.id
    max_delivery_attempts = 5
  }

  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }
}

# --- Ticket Events ---
resource "google_pubsub_topic" "ticket_events" {
  name                       = "tesserix-ticket-events"
  message_retention_duration = "604800s" # 7 days
}

resource "google_pubsub_topic" "ticket_events_dlq" {
  name = "tesserix-ticket-events-dlq"
}

# --- Subscription/Billing Events ---
resource "google_pubsub_topic" "subscription_events" {
  name                       = "tesserix-subscription-events"
  message_retention_duration = "604800s"
}

resource "google_pubsub_topic" "subscription_events_dlq" {
  name = "tesserix-subscription-events-dlq"
}

resource "google_pubsub_subscription" "audit_subscription_push" {
  name  = "audit-service-subscription-push"
  topic = google_pubsub_topic.subscription_events.id

  push_config {
    push_endpoint = "${google_cloud_run_v2_service.base["audit-service"].uri}/events"
    oidc_token {
      service_account_email = data.terraform_remote_state.iam.outputs.service_account_emails["audit-service"]
    }
  }

  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.subscription_events_dlq.id
    max_delivery_attempts = 5
  }

  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }
}

# =============================================================================
# MARKETPLACE EVENT TOPICS
# =============================================================================
# Pattern: services publish fire-and-forget events via go-shared/messaging.
# Push subscriptions can be added later when consumers are identified.
# =============================================================================

# --- Product Events ---
resource "google_pubsub_topic" "mp_product_events" {
  name                       = "mp-product-events"
  message_retention_duration = "604800s"
}

# --- Order Events ---
resource "google_pubsub_topic" "mp_order_events" {
  name                       = "mp-order-events"
  message_retention_duration = "604800s"
}

# --- Payment Events ---
resource "google_pubsub_topic" "mp_payment_events" {
  name                       = "mp-payment-events"
  message_retention_duration = "604800s"
}

# --- Inventory Events ---
resource "google_pubsub_topic" "mp_inventory_events" {
  name                       = "mp-inventory-events"
  message_retention_duration = "604800s"
}

# --- Staff Events ---
resource "google_pubsub_topic" "mp_staff_events" {
  name                       = "mp-staff-events"
  message_retention_duration = "604800s"
}

# --- Approval Events ---
resource "google_pubsub_topic" "mp_approval_events" {
  name                       = "mp-approval-events"
  message_retention_duration = "604800s"
}

# --- Gift Card Events ---
resource "google_pubsub_topic" "mp_gift_card_events" {
  name                       = "mp-gift-card-events"
  message_retention_duration = "604800s"
}

# --- Marketing Events ---
resource "google_pubsub_topic" "mp_marketing_events" {
  name                       = "mp-marketing-events"
  message_retention_duration = "604800s"
}

# --- Tax Events ---
resource "google_pubsub_topic" "mp_tax_events" {
  name                       = "mp-tax-events"
  message_retention_duration = "604800s"
}
