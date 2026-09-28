module "cloud_run_service" {
  source = "../../modules/cloud-run-service"

  project_id = var.project_id
  name       = "dockyard2sail-py"
  region     = var.region
  image      = var.image

  # Un servicio cerrado no se puede verificar con curl, y dev no guarda datos sensibles.
  allow_unauthenticated = true

  # dev se destruye y se recrea con frecuencia.
  deletion_protection = false
}

module "artifact_registry" {
  source = "../../modules/artifact-registry"

  project_id    = var.project_id
  repository_id = "dockyard2sail"
  location      = var.region
}
