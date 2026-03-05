# =============================================================================
# CLOUD TASKS — Async HTTP task queues
# =============================================================================
# Cost: $0 (free tier: 1M operations/month)
# Pattern: services enqueue tasks → Cloud Tasks calls Cloud Run endpoints
# =============================================================================

resource "google_cloud_tasks_queue" "order_processing" {
  name     = "order-processing"
  location = var.region

  rate_limits {
    max_dispatches_per_second = 10
    max_concurrent_dispatches = 5
  }

  retry_config {
    max_attempts = 5
    min_backoff  = "1s"
    max_backoff  = "120s"
    max_doublings = 4
  }
}

resource "google_cloud_tasks_queue" "email_sending" {
  name     = "email-sending"
  location = var.region

  rate_limits {
    max_dispatches_per_second = 5
    max_concurrent_dispatches = 3
  }

  retry_config {
    max_attempts = 3
    min_backoff  = "10s"
    max_backoff  = "300s"
  }
}
