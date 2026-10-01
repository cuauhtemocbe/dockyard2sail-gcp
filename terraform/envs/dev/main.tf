module "cloud_run_service" {
  source = "../../modules/cloud-run-service"

  project_id = var.project_id
  name       = "dockyard2sail-py"
  region     = var.region
  image      = var.image

  # Referencia a module.secrets (no a var.secret_env directo) para que el servicio espere a que el
  # secreto exista. El acceso de la SA no genera ciclo: Terraform depende por recurso, no por módulo.
  secret_env = { for name, id in var.secret_env : name => module.secrets.secret_ids[id] }

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

module "secrets" {
  source = "../../modules/secrets"

  project_id     = var.project_id
  secret_ids     = var.secret_ids
  accessor_email = module.cloud_run_service.service_account_email
}
