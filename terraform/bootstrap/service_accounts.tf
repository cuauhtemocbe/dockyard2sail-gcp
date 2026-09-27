# Service accounts de CI. Se autentican por WIF: no existen llaves JSON.

locals {
  # Roles de solo lectura de la SA `plan`, sobre todo el proyecto. Cubren lo que
  # `terraform plan` necesita leer al refrescar el estado de los módulos del template.
  plan_project_roles = toset([
    "roles/run.viewer",                     # servicios de Cloud Run
    "roles/artifactregistry.reader",        # repositorios de Artifact Registry
    "roles/secretmanager.viewer",           # secretos (metadatos, no sus valores)
    "roles/iam.securityReviewer",           # service accounts, WIF y políticas de IAM del proyecto
    "roles/iam.workloadIdentityPoolViewer", # leer el pool y el provider de WIF (securityReviewer no incluye iam.workloadIdentityPools.get)
  ])
}

resource "google_service_account" "plan" {
  project      = var.project_id
  account_id   = "${var.name_prefix}-plan"
  display_name = "CI plan (solo lectura)"
  description  = "Corre terraform plan desde cualquier ref del repositorio, incluidos los PRs. Sin permisos de escritura."

  depends_on = [google_project_service.required]
}

resource "google_project_iam_member" "plan" {
  for_each = local.plan_project_roles

  project = var.project_id
  role    = each.value
  member  = google_service_account.plan.member
}

# Lee el estado remoto. Sin escritura a propósito: `plan` corre con -lock=false, así que
# no necesita crear el objeto .tflock y no puede modificar el estado.
resource "google_storage_bucket_iam_member" "plan_state_reader" {
  bucket = google_storage_bucket.state.name
  role   = "roles/storage.objectViewer"
  member = google_service_account.plan.member
}

# Leer los metadatos del bucket (storage.buckets.get): objectViewer no lo incluye y el
# refresh de google_storage_bucket.state falla sin él. Solo lectura, solo este bucket.
resource "google_storage_bucket_iam_member" "plan_state_bucket_reader" {
  bucket = google_storage_bucket.state.name
  role   = "roles/storage.legacyBucketReader"
  member = google_service_account.plan.member
}

# Cualquier ref del repositorio autorizado puede usar la SA `plan`.
resource "google_service_account_iam_member" "plan_workload_identity" {
  service_account_id = google_service_account.plan.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${var.github_repository}"
}
