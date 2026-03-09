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

variable "identity_platform_api_key" {
  type        = string
  description = "Google Identity Platform Web API key"
  default     = ""
}

variable "cloudflare_zone_id" {
  type        = string
  description = "Cloudflare zone ID for mark8ly.com"
}

variable "cloudflare_account_id" {
  type        = string
  description = "Cloudflare account ID"
}
