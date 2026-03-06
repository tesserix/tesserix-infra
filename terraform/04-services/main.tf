terraform {
  required_version = ">= 1.5"
  required_providers {
    google = { source = "hashicorp/google", version = "~> 6.0" }
  }
  backend "gcs" {}
}

provider "google" {
  project               = var.project_id
  region                = var.region
  user_project_override = true
  billing_project       = var.project_id
}

data "terraform_remote_state" "core" {
  backend = "gcs"
  config = {
    bucket = var.state_bucket
    prefix = "02-core"
  }
}

data "terraform_remote_state" "iam" {
  backend = "gcs"
  config = {
    bucket = var.state_bucket
    prefix = "03-iam"
  }
}

locals {
  sql_connection = data.terraform_remote_state.core.outputs.cloud_sql_connection_name
  sa_emails      = data.terraform_remote_state.iam.outputs.service_account_emails
  gar_url        = "${var.region}-docker.pkg.dev/${var.project_id}/services"
}

# Remove old status-dashboard from state (replaced by status-service)
removed {
  from = google_cloud_run_v2_service.status_dashboard
  lifecycle {
    destroy = false
  }
}
