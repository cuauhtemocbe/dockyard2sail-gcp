output "url" {
  description = "URL del servicio de Cloud Run."
  value       = google_cloud_run_v2_service.this.uri
}

output "name" {
  description = "Nombre del servicio de Cloud Run."
  value       = google_cloud_run_v2_service.this.name
}

output "service_account_email" {
  description = "Correo de la SA de runtime."
  value       = google_service_account.runtime.email
}
