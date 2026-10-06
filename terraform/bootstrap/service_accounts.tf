# Service accounts de CI. Se autentican por WIF: no existen llaves JSON.

locals {
  # Roles de solo lectura de la SA `plan`, sobre todo el proyecto. Cubren lo que
  # `terraform plan` necesita leer al refrescar el estado de los módulos del template.
  plan_project_roles = toset([
    "roles/run.viewer",                        # servicios de Cloud Run
    "roles/artifactregistry.reader",           # repositorios de Artifact Registry
    "roles/secretmanager.viewer",              # secretos (metadatos, no sus valores)
    "roles/iam.securityReviewer",              # service accounts, WIF y políticas de IAM del proyecto
    "roles/serviceusage.serviceUsageConsumer", # usar el proyecto como quota project (user_project_override) y leer las APIs habilitadas
    "roles/iam.workloadIdentityPoolViewer",    # leer el pool y el provider de WIF (securityReviewer no incluye iam.workloadIdentityPools.get)
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

locals {
  # Roles de escritura de la SA `apply`, sobre todo el proyecto. Deliberadamente sin
  # owner, editor ni projectIamAdmin: con este último podría asignarse owner a sí misma.
  # Tampoco serviceAccountUser sobre el proyecto: lo recibe solo sobre la SA de runtime de cada
  # servicio, mediante el binding que crea el módulo cloud-run-service para sus `deployers`.
  # Los secretos van con un rol personalizado (abajo), no con secretmanager.admin.
  apply_project_roles = toset([
    "roles/run.admin",                         # crear y actualizar servicios de Cloud Run
    "roles/artifactregistry.admin",            # crear y administrar repositorios de Artifact Registry
    "roles/iam.serviceAccountAdmin",           # crear las SAs de runtime de los servicios y su binding de serviceAccountUser (sigue sobre el proyecto: hace falta para crear la SA; ver "Cosas que conviene saber" en el README)
    "roles/serviceusage.serviceUsageConsumer", # usar el proyecto como quota project (user_project_override)
  ])
}

# Reemplaza a roles/secretmanager.admin. Solo lo que Terraform usa en el módulo `secrets`:
# crear, leer, actualizar y borrar el contenedor del secreto, y su política de IAM (el binding
# de secretAccessor para la SA de runtime). Sin secretmanager.versions.access: la SA `apply`
# no puede leer el valor de ningún secreto. Tampoco versions.add: el valor lo carga una
# persona con `gcloud secrets versions add`. versions.get y versions.list devuelven solo
# metadatos (no el valor); quedan por si Cloud Run los pide al desplegar un servicio que
# monta `latest`. Se confirma en la verificación del README de bootstrap.
# secrets.setIamPolicy se queda aunque SonarQube lo marque (terraform:S6408, aceptado el
# 2026-10-06): el módulo `secrets` lo necesita para el binding de secretAccessor de la SA de
# runtime. La escalada (darse secretAccessor y leer el valor) está en specs/bootstrap-plan.md;
# la contiene que `apply` solo se obtiene desde `main`, protegida con enforce_admins.
resource "google_project_iam_custom_role" "apply_secrets" {
  project     = var.project_id
  role_id     = "${replace(var.name_prefix, "-", "_")}_apply_secrets"
  title       = "CI apply: secretos sin lectura de valores"
  description = "Administra contenedores de Secret Manager y su IAM, sin secretmanager.versions.access."
  permissions = [
    "secretmanager.secrets.create",
    "secretmanager.secrets.delete",
    "secretmanager.secrets.get",
    "secretmanager.secrets.list",
    "secretmanager.secrets.update",
    "secretmanager.secrets.getIamPolicy",
    "secretmanager.secrets.setIamPolicy",
    "secretmanager.versions.get",
    "secretmanager.versions.list",
  ]

  depends_on = [google_project_service.required]
}

resource "google_project_iam_member" "apply_secrets" {
  project = var.project_id
  role    = google_project_iam_custom_role.apply_secrets.id
  member  = google_service_account.apply.member
}

resource "google_service_account" "apply" {
  project      = var.project_id
  account_id   = "${var.name_prefix}-apply"
  display_name = "CI apply (escritura, solo main)"
  description  = "Corre terraform apply. Solo se puede usar desde refs/heads/main del repositorio."

  depends_on = [google_project_service.required]
}

resource "google_project_iam_member" "apply" {
  for_each = local.apply_project_roles

  project = var.project_id
  role    = each.value
  member  = google_service_account.apply.member
}

# Lee y escribe el estado remoto, incluido el objeto .tflock con el que se bloquea.
# Solo este bucket, no el proyecto.
resource "google_storage_bucket_iam_member" "apply_state_admin" {
  bucket = google_storage_bucket.state.name
  role   = "roles/storage.objectAdmin"
  member = google_service_account.apply.member
}

# Solo una ejecución sobre refs/heads/main del repositorio autorizado puede usar la SA
# `apply`. El atributo compuesto repo_ref evita que otro repositorio con una rama main
# obtenga la SA, y que otra rama del mismo repositorio lo haga.
resource "google_service_account_iam_member" "apply_workload_identity" {
  service_account_id = google_service_account.apply.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repo_ref/${var.github_repository}@refs/heads/main"
}
