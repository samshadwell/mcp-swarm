data "google_project" "project" {
  project_id = var.project
}

# Create a dedicated service account for the Cloud Run service
resource "google_service_account" "mcp_swarm_service_account" {
  account_id   = "mcp-swarm-service-sa"
  display_name = "MCP Swarm Service Account"
  description  = "Service account for the mcp-swarm Cloud Run service"
}

locals {
  garmin_port = 1234
}

resource "google_artifact_registry_repository" "ghcr-remote-repo" {
  location      = var.region
  repository_id = "ghcr-remote-repo"
  description   = "Pull-through cache for GitHub Container Registry (ghcr.io)"
  format        = "DOCKER"
  mode          = "REMOTE_REPOSITORY"
  remote_repository_config {
    common_repository {
      uri = "https://ghcr.io"
    }
  }

  # Cleanup policy to minimize costs. This is a cache, so don't need to keep much there
  cleanup_policies {
    id     = "delete-old-images"
    action = "DELETE"
    condition {
      older_than = "7d"
    }
  }
  cleanup_policies {
    id     = "keep-latest"
    action = "KEEP"
    most_recent_versions {
      keep_count = 2
    }
  }
}

# Reference secrets. Created/populated by bootstrap-secrets.sh
data "google_secret_manager_secret" "garmin-email" {
  secret_id = "garmin-email"
  project   = data.google_project.project.project_id
}
data "google_secret_manager_secret" "garmin-pw" {
  secret_id = "garmin-pw"
  project   = data.google_project.project.project_id
}
data "google_secret_manager_secret" "oauth2-authenticated-emails" {
  secret_id = "oauth2-authenticated-emails"
  project   = data.google_project.project.project_id
}
data "google_secret_manager_secret" "oauth2-client-secret" {
  secret_id = "oauth2-client-secret"
  project   = data.google_project.project.project_id
}
data "google_secret_manager_secret" "oauth2-cookie-secret" {
  secret_id = "oauth2-cookie-secret"
  project   = data.google_project.project.project_id
}

resource "google_cloud_run_v2_service" "mcp-swarm-service" {
  name                = "mcp-swarm-service"
  location            = var.region
  deletion_protection = false
  ingress             = "INGRESS_TRAFFIC_ALL"

  template {
    service_account = google_service_account.mcp_swarm_service_account.email

    scaling {
      min_instance_count = 0
      max_instance_count = 1
    }

    # Sidecar container: garmin-mcp
    # No ports block = not the ingress container, only accessible via localhost
    containers {
      name  = "garmin-mcp"
      image = "${google_artifact_registry_repository.ghcr-remote-repo.registry_uri}/${var.garmin-image}"
      resources {
        limits = {
          cpu = "1"
          memory = "512Mi"
        }
        startup_cpu_boost = true
        cpu_idle          = true
      }

      env {
        name  = "PORT"
        value = tostring(local.garmin_port)
      }

      env {
        name  = "GARMIN_EMAIL_FILE"
        value = "/secrets/garmin-email/garmin-email"
      }

      env {
        name  = "GARMIN_PASSWORD_FILE"
        value = "/secrets/garmin-pw/garmin-pw"
      }

      volume_mounts {
        name       = "garmin-email"
        mount_path = "/secrets/garmin-email"
      }

      volume_mounts {
        name       = "garmin-pw"
        mount_path = "/secrets/garmin-pw"
      }

      startup_probe {
        http_get {
          path = "/status"
          port = local.garmin_port
        }
        initial_delay_seconds = 0
        timeout_seconds       = 1
        period_seconds        = 1
        failure_threshold     = 20
      }

      liveness_probe {
        http_get {
          path = "/status"
          port = local.garmin_port
        }
        initial_delay_seconds = 0
        timeout_seconds       = 3
        period_seconds        = 10
        failure_threshold     = 3
      }
    }

    # Main container: oauth2-proxy (receives external traffic)
    # Only this container has a port exposed, making it the ingress container
    containers {
      name  = "oauth2-proxy"
      image = "${google_artifact_registry_repository.ghcr-remote-repo.registry_uri}/${var.oauth2-image}"

      # Exposing a port marks this as the ingress container
      ports {
        container_port = 8080
      }

      resources {
        limits = {
          cpu = "1"
          memory = "512Mi"
        }
        startup_cpu_boost = false
        cpu_idle          = true
      }

      env {
        name  = "OAUTH2_PROXY_CLIENT_ID"
        value = var.oauth2-client-id
      }

      env {
        name  = "OAUTH2_PROXY_COOKIE_SECURE"
        value = "true"
      }

      env {
        name  = "OAUTH2_PROXY_COOKIE_DOMAIN"
        value = var.host-domain
      }

      env {
        name  = "OAUTH2_PROXY_WHITELIST_DOMAIN"
        value = var.host-domain
      }

      env {
        name  = "OAUTH2_PROXY_CODE_CHALLENGE_METHOD"
        value = "S256"
      }

      env {
        name  = "OAUTH2_PROXY_REDIRECT_URL"
        value = "https://${var.host-domain}/oauth2/callback"
      }

      env {
        name  = "OAUTH2_PROXY_UPSTREAMS"
        value = "http://127.0.0.1:${local.garmin_port}"
      }

      env {
        name  = "OAUTH2_PROXY_AUTHENTICATED_EMAILS_FILE"
        value = "/secrets/oauth2-authenticated-emails/oauth2-authenticated-emails"
      }

      env {
        name  = "OAUTH2_PROXY_CLIENT_SECRET_FILE"
        value = "/secrets/oauth2-client-secret/oauth2-client-secret"
      }

      env {
        name  = "OAUTH2_PROXY_COOKIE_SECRET_FILE"
        value = "/secrets/oauth2-cookie-secret/oauth2-cookie-secret"
      }

      volume_mounts {
        name       = "oauth2-authenticated-emails"
        mount_path = "/secrets/oauth2-authenticated-emails"
      }

      volume_mounts {
        name       = "oauth2-client-secret"
        mount_path = "/secrets/oauth2-client-secret"
      }

      volume_mounts {
        name       = "oauth2-cookie-secret"
        mount_path = "/secrets/oauth2-cookie-secret"
      }

      startup_probe {
        http_get {
          path = "/ready"
        }
        initial_delay_seconds = 0
        timeout_seconds       = 1
        period_seconds        = 1
        failure_threshold     = 15
      }

      liveness_probe {
        http_get {
          path = "/ping"
        }
        initial_delay_seconds = 0
        timeout_seconds       = 3
        period_seconds        = 10
        failure_threshold     = 3
      }

      depends_on = ["garmin-mcp"]
    }

    volumes {
      name = "garmin-email"
      secret {
        secret       = data.google_secret_manager_secret.garmin-email.secret_id
        items {
          version = "latest"
          path    = "garmin-email"
        }
      }
    }

    volumes {
      name = "garmin-pw"
      secret {
        secret       = data.google_secret_manager_secret.garmin-pw.secret_id
        items {
          version = "latest"
          path    = "garmin-pw"
        }
      }
    }

    volumes {
      name = "oauth2-authenticated-emails"
      secret {
        secret       = data.google_secret_manager_secret.oauth2-authenticated-emails.secret_id
        items {
          version = "latest"
          path    = "oauth2-authenticated-emails"
        }
      }
    }

    volumes {
      name = "oauth2-client-secret"
      secret {
        secret       = data.google_secret_manager_secret.oauth2-client-secret.secret_id
        items {
          version = "latest"
          path    = "oauth2-client-secret"
        }
      }
    }

    volumes {
      name = "oauth2-cookie-secret"
      secret {
        secret       = data.google_secret_manager_secret.oauth2-cookie-secret.secret_id
        items {
          version = "latest"
          path    = "oauth2-cookie-secret"
        }
      }
    }
  }
}

# IAM permissions for mcp-swarm-service to access secrets
resource "google_secret_manager_secret_iam_member" "garmin-email-access" {
  secret_id = data.google_secret_manager_secret.garmin-email.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.mcp_swarm_service_account.email}"
}

resource "google_secret_manager_secret_iam_member" "garmin-pw-access" {
  secret_id = data.google_secret_manager_secret.garmin-pw.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.mcp_swarm_service_account.email}"
}

resource "google_secret_manager_secret_iam_member" "oauth2-authenticated-emails-access" {
  secret_id = data.google_secret_manager_secret.oauth2-authenticated-emails.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.mcp_swarm_service_account.email}"
}

resource "google_secret_manager_secret_iam_member" "oauth2-client-secret-access" {
  secret_id = data.google_secret_manager_secret.oauth2-client-secret.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.mcp_swarm_service_account.email}"
}

resource "google_secret_manager_secret_iam_member" "oauth2-cookie-secret-access" {
  secret_id = data.google_secret_manager_secret.oauth2-cookie-secret.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.mcp_swarm_service_account.email}"
}

# Allow public (unauthenticated) access to the Cloud Run service
resource "google_cloud_run_v2_service_iam_member" "public-access" {
  name     = google_cloud_run_v2_service.mcp-swarm-service.name
  location = google_cloud_run_v2_service.mcp-swarm-service.location
  role     = "roles/run.invoker"
  member   = "allUsers"
}
