resource "google_kms_key_ring" "main" {
  name     = "tesserix-keyring"
  location = var.region
}

resource "google_kms_crypto_key" "data_encryption" {
  name     = "data-encryption-key"
  key_ring = google_kms_key_ring.main.id

  rotation_period = "7776000s" # 90 days

  lifecycle {
    prevent_destroy = true
  }
}
