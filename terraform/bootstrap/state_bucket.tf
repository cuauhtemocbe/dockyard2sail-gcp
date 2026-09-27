resource "google_storage_bucket" "state" {
  name     = "${var.project_id}-tfstate"
  project  = var.project_id
  location = var.region

  storage_class               = "STANDARD"
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  # Un bucket con estado no se borra por accidente: force_destroy impide
  # borrarlo con objetos dentro, y prevent_destroy bloquea `terraform destroy`.
  force_destroy = false

  # El versionado permite recuperar un estado dañado o sobrescrito.
  versioning {
    enabled = true
  }

  # Borra las versiones no vigentes después de N días para que el bucket
  # no crezca sin límite. La versión vigente nunca se toca.
  lifecycle_rule {
    action {
      type = "Delete"
    }

    condition {
      with_state                 = "ARCHIVED"
      days_since_noncurrent_time = var.state_version_retention_days
    }
  }

  lifecycle {
    prevent_destroy = true
  }

  depends_on = [google_project_service.required]
}
