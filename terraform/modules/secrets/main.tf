# Solo el contenedor del secreto: no se crea ninguna versión, así el valor nunca pasa por el
# código, el plan ni el estado.
resource "google_secret_manager_secret" "this" {
  for_each = var.secret_ids

  project   = var.project_id
  secret_id = each.value

  replication {
    auto {}
  }
}

# El acceso se da sobre cada secreto, no sobre el proyecto: la SA lee solo los que se le asignan.
resource "google_secret_manager_secret_iam_member" "accessor" {
  for_each = var.secret_ids

  project   = var.project_id
  secret_id = google_secret_manager_secret.this[each.value].secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${var.accessor_email}"
}
