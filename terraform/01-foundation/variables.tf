variable "project_id" {
  type        = string
  description = "GCP project ID"
}

variable "project_number" {
  type        = string
  description = "GCP project number (numeric)"
}

variable "region" {
  type        = string
  description = "Primary GCP region"
  default     = "asia-south1"
}

variable "billing_account_id" {
  type        = string
  description = "GCP billing account ID"
}
