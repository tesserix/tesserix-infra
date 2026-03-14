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

# Kargo variables removed — re-add when Kargo is re-enabled
