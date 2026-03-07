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
    push_endpoint = "${google_cloud_run_v2_service.standard["audit-service"].uri}/events"
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
    push_endpoint = "${google_cloud_run_v2_service.standard["notification-service"].uri}/events"
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
