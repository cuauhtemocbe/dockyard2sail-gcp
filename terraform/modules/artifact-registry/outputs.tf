output "repository_url" {
  description = "Prefijo de las imágenes: <location>-docker.pkg.dev/<proyecto>/<repositorio>. Se le agrega /<imagen>:<tag>."
  value       = "${google_artifact_registry_repository.this.location}-docker.pkg.dev/${google_artifact_registry_repository.this.project}/${google_artifact_registry_repository.this.repository_id}"
}

output "repository_id" {
  description = "Nombre del repositorio."
  value       = google_artifact_registry_repository.this.repository_id
}
