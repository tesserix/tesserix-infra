# =============================================================================
# PLATFORM SERVICES — SUPERSEDED
# =============================================================================
# All Cloud Run service definitions previously in this file have been replaced
# by the for_each approach. See:
#
#   services-config.tf      — locals maps (standard_db_services, simple_services,
#                             all_service_uris, public_services)
#   cloud-run-standard.tf   — google_cloud_run_v2_service.standard (for_each)
#                             google_cloud_run_v2_service.simple   (for_each)
#                             google_cloud_run_service_iam_member.public_access
#   cloud-run-special.tf    — openfga, auth-bff, tesserix-home,
#                             marketplace-onboarding, marketplace-admin,
#                             status-service
#
# This file is intentionally empty. It is kept to preserve git history context.
# =============================================================================
