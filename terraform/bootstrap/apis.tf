locals {
  # APIs que necesitan este módulo y los módulos siguientes del template.
  required_apis = toset([
    "iam.googleapis.com",                  # service accounts y WIF
    "iamcredentials.googleapis.com",       # generar tokens al usar una service account
    "sts.googleapis.com",                  # intercambiar el token OIDC de GitHub
    "cloudresourcemanager.googleapis.com", # leer y modificar el IAM del proyecto
    "serviceusage.googleapis.com",         # habilitar APIs desde Terraform
    "storage.googleapis.com",              # bucket de estado
    "run.googleapis.com",                  # Cloud Run
    "artifactregistry.googleapis.com",     # imágenes del contenedor
    "secretmanager.googleapis.com",        # secretos de la app
  ])
}

resource "google_project_service" "required" {
  for_each = local.required_apis

  project = var.project_id
  service = each.value

  # Apagar el bootstrap no debe apagar APIs que usan otros recursos.
  disable_on_destroy = false
}
