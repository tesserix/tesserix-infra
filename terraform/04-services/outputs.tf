output "service_urls" {
  value = {
    "auth-bff"               = google_cloud_run_v2_service.auth_bff.uri
    "openfga"                = google_cloud_run_v2_service.openfga.uri
    "audit-service"          = google_cloud_run_v2_service.audit_service.uri
    "tenant-service"         = google_cloud_run_v2_service.tenant_service.uri
    "notification-service"   = google_cloud_run_v2_service.notification_service.uri
    "tesserix-home"          = google_cloud_run_v2_service.tesserix_home.uri
    "feature-flags-service"  = google_cloud_run_v2_service.feature_flags.uri
    "tickets-service"        = google_cloud_run_v2_service.tickets_service.uri
    "status-service"         = google_cloud_run_v2_service.status_service.uri
    "location-service"       = google_cloud_run_v2_service.location_service.uri
    "tenant-router-service"  = google_cloud_run_v2_service.tenant_router_service.uri
    "marketplace-onboarding" = google_cloud_run_v2_service.marketplace_onboarding.uri
  }
}
