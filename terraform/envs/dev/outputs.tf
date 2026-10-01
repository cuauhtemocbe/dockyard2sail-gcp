output "service_url" {
  description = "URL del servicio de Cloud Run."
  value       = module.cloud_run_service.url
}

output "runtime_service_account" {
  description = "Correo de la SA de runtime del servicio."
  value       = module.cloud_run_service.service_account_email
}

output "repository_url" {
  description = "Prefijo de las imágenes del repositorio de Artifact Registry."
  value       = module.artifact_registry.repository_url
}
