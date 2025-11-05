data "google_project" "project" {
  project_id = var.project
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

resource "google_artifact_registry_repository" "mcp-swarm-images" {
  repository_id          = "mcp-swarm-images"
  description            = "Docker images for MCP Swarm"
  format                 = "DOCKER"
  cleanup_policy_dry_run = false

  cleanup_policies {
    id     = "delete-old"
    action = "DELETE"
    condition {
      tag_state  = "ANY"
      older_than = "30d"
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

resource "google_cloud_run_v2_service" "mcp-swarm-service" {
  name                = "mcp-swarm-service"
  location            = var.region
  deletion_protection = false
  ingress             = "INGRESS_TRAFFIC_ALL"

  template {
    scaling {
      min_instance_count = 0
      max_instance_count = 1
    }

    # Sidecar container: garmin-mcp
    # No ports block = not the ingress container, only accessible via localhost
    containers {
      name  = "garmin-mcp"
      image = "${google_artifact_registry_repository.mcp-swarm-images.registry_uri}/${var.garmin-image-name}:${var.garmin-image-tag}"

      env {
        name  = "PORT"
        value = "1234"
      }

      env {
        name  = "GARMIN_EMAIL_FILE"
        value = "/secrets/garmin-email"
      }

      env {
        name  = "GARMIN_PASSWORD_FILE"
        value = "/secrets/garmin-pw"
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
          port = 1234
        }
        initial_delay_seconds = 0
        timeout_seconds       = 1
        period_seconds        = 1
        failure_threshold     = 10
      }

      liveness_probe {
        http_get {
          path = "/status"
          port = 1234
        }
        initial_delay_seconds = 0
        timeout_seconds       = 1
        period_seconds        = 10
        failure_threshold     = 3
      }
    }

    # Main container: oauth2-proxy (receives external traffic)
    # Only this container has a port exposed, making it the ingress container
    containers {
      name  = "oauth2-proxy"
      image = "${google_artifact_registry_repository.mcp-swarm-images.registry_uri}/${var.oauth2-image-name}:${var.oauth2-image-tag}"

      # Exposing a port marks this as the ingress container
      ports {
        container_port = 8080
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
        name  = "OAUTH2_PROXY_REDIRECT_URL"
        value = "https://${var.host-domain}/oauth2/callback"
      }

      env {
        name  = "OAUTH2_PROXY_UPSTREAMS"
        value = "http://127.0.0.1:8081"
      }

      env {
        name  = "OAUTH2_PROXY_AUTHENTICATED_EMAILS_FILE"
        value = "/secrets/oauth2-authenticated-emails"
      }

      env {
        name  = "OAUTH2_PROXY_CLIENT_SECRET_FILE"
        value = "/secrets/oauth2-client-secret"
      }

      env {
        name  = "OAUTH2_PROXY_COOKIE_SECRET_FILE"
        value = "/secrets/oauth2-cookie-secret"
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
        timeout_seconds       = 1
        period_seconds        = 10
        failure_threshold     = 3
      }

      depends_on = ["garmin-mcp"]
    }

    volumes {
      name = "garmin-email"
      secret {
        secret       = data.google_secret_manager_secret.garmin-email.secret_id
        default_mode = 0444
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
        default_mode = 0444
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
        default_mode = 0444
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
        default_mode = 0444
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
        default_mode = 0444
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
  member    = "serviceAccount:${google_cloud_run_v2_service.mcp-swarm-service.template[0].service_account}"
}

resource "google_secret_manager_secret_iam_member" "garmin-pw-access" {
  secret_id = data.google_secret_manager_secret.garmin-pw.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_cloud_run_v2_service.mcp-swarm-service.template[0].service_account}"
}

resource "google_secret_manager_secret_iam_member" "oauth2-authenticated-emails-access" {
  secret_id = data.google_secret_manager_secret.oauth2-authenticated-emails.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_cloud_run_v2_service.mcp-swarm-service.template[0].service_account}"
}

resource "google_secret_manager_secret_iam_member" "oauth2-client-secret-access" {
  secret_id = data.google_secret_manager_secret.oauth2-client-secret.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_cloud_run_v2_service.mcp-swarm-service.template[0].service_account}"
}

resource "google_secret_manager_secret_iam_member" "oauth2-cookie-secret-access" {
  secret_id = data.google_secret_manager_secret.oauth2-cookie-secret.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_cloud_run_v2_service.mcp-swarm-service.template[0].service_account}"
}
