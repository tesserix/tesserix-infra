variable "project_id" {
  type = string
}

variable "region" {
  type    = string
  default = "asia-south1"
}

variable "state_bucket" {
  type = string
}

variable "argocd_repo_url" {
  type    = string
  default = "https://github.com/tesserix/tesserix-infra.git"
}

variable "kargo_admin_password_hash" {
  type        = string
  sensitive   = true
  description = "Bcrypt hash of the Kargo admin password"
}

variable "kargo_token_signing_key" {
  type        = string
  sensitive   = true
  description = "Base64-encoded key for signing Kargo API tokens"
}
