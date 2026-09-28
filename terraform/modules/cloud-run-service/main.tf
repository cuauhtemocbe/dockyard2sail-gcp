# La SA con la que corre la app. No recibe ningún rol de proyecto: los accesos que necesite
# (por ejemplo, leer un secreto) se dan sobre cada recurso.
resource "google_service_account" "runtime" {
  project      = var.project_id
  account_id   = "${var.name}-runtime"
  display_name = "Runtime de ${var.name}"
  description  = "Identidad del servicio de Cloud Run ${var.name}. Sin roles de proyecto."
}

resource "google_cloud_run_v2_service" "this" {
  project  = var.project_id
  name     = var.name
  location = var.region

  deletion_protection = var.deletion_protection

  # Desactiva la comprobación del invocador en vez de dar roles/run.invoker a allUsers: es lo
  # que recomienda Google y funciona aunque la organización restrinja el IAM a allUsers.
  invoker_iam_disabled = var.allow_unauthenticated

  template {
    service_account = google_service_account.runtime.email

    scaling {
      min_instance_count = var.min_instances
    }

    containers {
      image = var.image

      dynamic "env" {
        for_each = var.secret_env

        content {
          name = env.key

          value_source {
            secret_key_ref {
              secret  = env.value
              version = "latest"
            }
          }
        }
      }
    }
  }

  lifecycle {
    ignore_changes = [
      # `gcloud run deploy` cambia la imagen; sin esto, cada plan propondría volver al placeholder.
      template[0].containers[0].image,
      # gcloud escribe estos dos campos en cada despliegue.
      client,
      client_version,
    ]
  }
}
