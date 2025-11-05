variable "project" {
  type        = string
  description = "Google Cloud Project ID"
}

variable "region" {
  type        = string
  description = "Google Cloud region"
}

variable "oauth2-client-id" {
  type        = string
  description = "Google OAuth 2.0 Client ID (managed outside Terraform)"
}

variable "garmin-image" {
  type = string
}

variable "oauth2-image" {
  type = string
}

variable "host-domain" {
  type = string
}
