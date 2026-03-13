terraform {
  backend "gcs" {
    prefix = "06-k8s-bootstrap"
  }

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.17"
    }
    kubectl = {
      source  = "alekc/kubectl"
      version = "~> 2.1"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

data "terraform_remote_state" "gke" {
  backend = "gcs"
  config = {
    bucket = var.state_bucket
    prefix = "05-gke"
  }
}

data "google_client_config" "default" {}

provider "helm" {
  kubernetes {
    host                   = "https://${data.terraform_remote_state.gke.outputs.cluster_endpoint}"
    token                  = data.google_client_config.default.access_token
    cluster_ca_certificate = base64decode(data.terraform_remote_state.gke.outputs.cluster_ca_certificate)
  }
}

provider "kubectl" {
  host                   = "https://${data.terraform_remote_state.gke.outputs.cluster_endpoint}"
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(data.terraform_remote_state.gke.outputs.cluster_ca_certificate)
  load_config_file       = false
}
