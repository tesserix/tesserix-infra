# =============================================================================
# GKE CLUSTER VARIABLES
# =============================================================================

variable "project_id" {
  type = string
}

variable "region" {
  type    = string
  default = "asia-south1"
}

variable "cluster_name" {
  type    = string
  default = "tesserix-prod"
}

variable "state_bucket" {
  type = string
}

# VPC reference (from 02-core remote state)
variable "vpc_name" {
  type    = string
  default = "tesserix-vpc"
}

# Master authorized networks (CI + developer access)
variable "master_authorized_cidrs" {
  type = map(string)
  default = {
    "cloudshell" = "35.235.240.0/20"
  }
}
