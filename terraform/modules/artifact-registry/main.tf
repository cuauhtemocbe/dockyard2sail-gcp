resource "google_artifact_registry_repository" "this" {
  project       = var.project_id
  repository_id = var.repository_id
  location      = var.location
  format        = "DOCKER"
  description   = "Imágenes de contenedor de ${var.repository_id}"

  cleanup_policy_dry_run = var.cleanup_policy_dry_run

  # Conserva las últimas N versiones, con o sin tag. keep_count no admite filtro por tag ni se
  # combina con otras condiciones en la misma política, por eso el borrado va en otra.
  cleanup_policies {
    id     = "keep-recent-versions"
    action = "KEEP"

    most_recent_versions {
      keep_count = var.keep_count
    }
  }

  # Borra las versiones sin tag viejas. Si una versión cumple esta y la anterior, KEEP gana.
  cleanup_policies {
    id     = "delete-old-untagged"
    action = "DELETE"

    condition {
      tag_state  = "UNTAGGED"
      older_than = "${var.untagged_max_age_days * 86400}s"
    }
  }
}
