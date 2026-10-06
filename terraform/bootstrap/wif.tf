locals {
  # Solo se aceptan tokens del repositorio indicado, por nombre y por ID numérico:
  # el nombre de un repositorio borrado lo puede reutilizar otra persona; el ID no.
  github_repository_condition = "assertion.repository == '${var.github_repository}' && assertion.repository_id == '${var.github_repository_id}'"
}

resource "google_iam_workload_identity_pool" "github" {
  project                   = var.project_id
  workload_identity_pool_id = "${var.name_prefix}-github"
  display_name              = "GitHub Actions"
  description               = "Identidades de GitHub Actions del repositorio ${var.github_repository}."

  depends_on = [google_project_service.required]
}

resource "google_iam_workload_identity_pool_provider" "github" {
  project                            = var.project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github"
  display_name                       = "GitHub OIDC"

  # El proveedor rechaza cualquier token que no venga del repositorio autorizado,
  # antes de que se evalúe qué service account intenta usar.
  attribute_condition = local.github_repository_condition

  attribute_mapping = {
    "google.subject"          = "assertion.sub"
    "attribute.repository"    = "assertion.repository"
    "attribute.ref"           = "assertion.ref"
    "attribute.repository_id" = "assertion.repository_id"

    # Repositorio y rama en un solo atributo: un permiso de WIF solo puede filtrar
    # por un atributo, y la SA `apply` necesita exigir los dos a la vez.
    "attribute.repo_ref" = "assertion.repository + '@' + assertion.ref"
  }

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}
