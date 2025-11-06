variable "project" {
  type        = string
  description = "Google Cloud Project ID"
}

variable "region" {
  type        = string
  description = "Google Cloud region"
}

variable "oauth2_client_id" {
  type        = string
  description = "Google OAuth 2.0 Client ID (managed outside Terraform)"
}

variable "garmin_image" {
  type = string
}

variable "oauth2_image" {
  type = string
}

variable "host_domain" {
  type = string
}
