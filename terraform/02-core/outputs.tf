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
