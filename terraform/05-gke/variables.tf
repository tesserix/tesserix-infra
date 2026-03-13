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

variable "state_bucket" {
  type = string
}

# Master authorized networks (CI + developer access)
variable "master_authorized_cidrs" {
  type = map(string)
  default = {
    "cloudshell" = "35.235.240.0/20"
    "mahesh"     = "104.30.167.39/32"
  }
}
