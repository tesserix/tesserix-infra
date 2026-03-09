# All service URIs — merged from base, dependent, simple, and special resources.
output "service_urls" {
  value = merge(
    { for k, v in google_cloud_run_v2_service.base : k => v.uri },
    { for k, v in google_cloud_run_v2_service.dependent : k => v.uri },
    { for k, v in google_cloud_run_v2_service.simple : k => v.uri },
    {
      "openfga"                = google_cloud_run_v2_service.openfga.uri
      "auth-bff"               = google_cloud_run_v2_service.auth_bff.uri
      "tesserix-home"          = google_cloud_run_v2_service.tesserix_home.uri
      "marketplace-onboarding" = google_cloud_run_v2_service.marketplace_onboarding.uri
      "marketplace-admin"      = google_cloud_run_v2_service.marketplace_admin.uri
      "status-service"         = google_cloud_run_v2_service.status_service.uri
      "mp-storefront"          = google_cloud_run_v2_service.mp_storefront.uri
    }
  )
}
