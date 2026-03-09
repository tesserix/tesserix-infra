output "cloud_sql_connection_name" {
  value = google_sql_database_instance.main.connection_name
}

output "cloud_sql_private_ip" {
  value = google_sql_database_instance.main.private_ip_address
}

output "vpc_id" {
  value = google_compute_network.main.id
}

output "assets_bucket" {
  value = google_storage_bucket.assets.name
}

output "public_assets_bucket" {
  value = google_storage_bucket.public_assets.name
}

output "backups_bucket" {
  value = google_storage_bucket.backups.name
}

# Identity Platform tenant IDs
output "gip_tenant_platform" {
  value = google_identity_platform_tenant.platform.name
  # Actual value: Platform-e1vyf
}

output "gip_tenant_mp_internal" {
  value = google_identity_platform_tenant.mp_internal.name
  # Actual value: MP-Internal-uidfu
}

output "gip_tenant_mp_customer" {
  value = google_identity_platform_tenant.mp_customer.name
  # Actual value: MP-Customer-cgob2
}
