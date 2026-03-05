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

# Reference outputs from 02-core
data "terraform_remote_state" "core" {
  backend = "gcs"
  config = {
    bucket = var.state_bucket
    prefix = "02-core"
  }
}
