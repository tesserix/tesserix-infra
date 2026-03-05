variable "project_id" {
  type = string
}

variable "region" {
  type    = string
  default = "asia-south1"
}

variable "state_bucket" {
  type        = string
  description = "GCS bucket for Terraform state"
}

variable "github_org" {
  type        = string
  description = "GitHub organization name for WIF"
  default     = "tesserix"
}
